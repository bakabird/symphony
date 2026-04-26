defmodule SymphonyElixir.AgentBackend.AcpStdio do
  @moduledoc """
  ACP-over-stdio backend for agents such as `opencode acp`.
  """

  @behaviour SymphonyElixir.AgentBackend

  require Logger

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.AgentBackend.CommandPort
  alias SymphonyElixir.Config

  @backend_name :acp_stdio
  @initialize_id 1
  @session_new_id 2
  @session_close_id 3

  @impl true
  def start_session(context, _opts) do
    backend_settings = Config.agent_backend_settings()
    workspace = AgentBackend.value_from(context, :workspace_path)
    worker_host = AgentBackend.value_from(context, :worker_host)
    on_event = AgentBackend.value_from(context, :on_event) || fn _event -> :ok end

    with {:ok, command_session} <- CommandPort.start(workspace, worker_host, backend_settings.command) do
      with :ok <- send_initialize(command_session.port),
           {:ok, initialize_result} <- await_response(command_session.port, @initialize_id, backend_settings.read_timeout_ms),
           {:ok, session_id} <- create_session(command_session.port, command_session.workspace, backend_settings.read_timeout_ms) do
        {:ok,
         %{
           metadata: command_session.metadata,
           on_event: on_event,
           port: command_session.port,
           read_timeout_ms: backend_settings.read_timeout_ms,
           session_capabilities: session_capabilities(initialize_result),
           session_id: session_id,
           turn_timeout_ms: backend_settings.turn_timeout_ms,
           worker_host: command_session.worker_host,
           workspace: command_session.workspace
         }}
      else
        {:error, reason} = error ->
          Logger.warning("ACP backend failed to start session: #{inspect(reason)}")
          CommandPort.stop(command_session)
          error
      end
    end
  end

  @impl true
  def run_turn(session, turn, _opts) do
    prompt_id = 1_000 + turn.turn_number
    turn_id = Integer.to_string(turn.turn_number)
    session_id = composite_session_id(session.session_id, turn_id)

    emit_event(
      session,
      %{
        event: :session_started,
        session_id: session_id,
        thread_id: session.session_id,
        turn_id: turn_id,
        payload: %{"method" => "session/prompt"}
      }
    )

    CommandPort.send_json(session.port, %{
      "jsonrpc" => "2.0",
      "id" => prompt_id,
      "method" => "session/prompt",
      "params" => %{
        "sessionId" => session.session_id,
        "prompt" => [
          %{
            "type" => "text",
            "text" => turn.prompt
          }
        ]
      }
    })

    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  @impl true
  def stop_session(%{port: port, read_timeout_ms: read_timeout_ms, session_capabilities: capabilities, session_id: session_id} = session)
      when is_port(port) do
    if close_supported?(capabilities) do
      CommandPort.send_json(port, %{
        "jsonrpc" => "2.0",
        "id" => @session_close_id,
        "method" => "session/close",
        "params" => %{
          "sessionId" => session_id
        }
      })

      _ = await_response(port, @session_close_id, read_timeout_ms)
    end

    CommandPort.stop(session)
  end

  def stop_session(session), do: CommandPort.stop(session)

  defp send_initialize(port) when is_port(port) do
    CommandPort.send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => @initialize_id,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => 1,
        "clientCapabilities" => %{},
        "clientInfo" => %{
          "name" => "symphony",
          "title" => "Symphony",
          "version" => "0.1.0"
        }
      }
    })
  end

  defp create_session(port, workspace, timeout_ms) when is_port(port) and is_binary(workspace) do
    CommandPort.send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => @session_new_id,
      "method" => "session/new",
      "params" => %{
        "cwd" => workspace,
        "mcpServers" => []
      }
    })

    case await_response(port, @session_new_id, timeout_ms) do
      {:ok, %{"sessionId" => session_id}} when is_binary(session_id) ->
        {:ok, session_id}

      {:ok, payload} ->
        {:error, {:invalid_session_response, payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_response(port, request_id, timeout_ms) when is_port(port) do
    case CommandPort.receive_json(port, timeout_ms) do
      {:ok, %{"id" => ^request_id, "result" => result}, _pending_line} ->
        {:ok, result}

      {:ok, %{"id" => ^request_id, "error" => error}, _pending_line} ->
        {:error, {:json_rpc_error, error}}

      {:ok, _payload, _pending_line} ->
        await_response(port, request_id, timeout_ms)

      {:malformed, raw, _pending_line} ->
        Logger.debug("ACP startup emitted non-JSON output: #{inspect(raw)}")
        await_response(port, request_id, timeout_ms)

      {:error, :timeout} ->
        {:error, :read_timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_prompt_completion(session, prompt_id, session_id, turn_id) do
    case CommandPort.receive_json(session.port, session.turn_timeout_ms) do
      {:ok, payload, _pending_line} ->
        handle_prompt_completion_payload(session, prompt_id, session_id, turn_id, payload)

      {:malformed, raw, _pending_line} ->
        handle_prompt_completion_malformed(session, prompt_id, session_id, turn_id, raw)

      {:error, :timeout} ->
        {:error, :turn_timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_prompt_completion_payload(
         session,
         prompt_id,
         session_id,
         turn_id,
         %{"id" => request_id, "result" => result} = payload
       )
       when request_id == prompt_id do
    emit_prompt_event(session, session_id, turn_id, :turn_completed, payload)

    {:ok,
     %{
       backend: @backend_name,
       result: result,
       session_id: session_id,
       thread_id: session.session_id,
       turn_id: turn_id
     }}
  end

  defp handle_prompt_completion_payload(
         session,
         prompt_id,
         session_id,
         turn_id,
         %{"id" => request_id, "error" => error} = payload
       )
       when request_id == prompt_id do
    emit_prompt_event(session, session_id, turn_id, :turn_failed, payload)
    {:error, {:json_rpc_error, error}}
  end

  defp handle_prompt_completion_payload(session, prompt_id, session_id, turn_id, %{"method" => "session/update"} = payload) do
    emit_prompt_event(session, session_id, turn_id, :notification, payload)
    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  defp handle_prompt_completion_payload(
         session,
         prompt_id,
         session_id,
         turn_id,
         %{"id" => request_id, "method" => "session/request_permission", "params" => params} = payload
       )
       when is_integer(request_id) or is_binary(request_id) do
    respond_to_permission_request(session.port, request_id, params)
    emit_prompt_event(session, session_id, turn_id, :notification, payload)
    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  defp handle_prompt_completion_payload(
         session,
         prompt_id,
         session_id,
         turn_id,
         %{"id" => request_id, "method" => method} = payload
       )
       when (is_integer(request_id) or is_binary(request_id)) and is_binary(method) do
    respond_method_not_found(session.port, request_id, method)
    emit_prompt_event(session, session_id, turn_id, :notification, payload)
    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  defp handle_prompt_completion_payload(session, prompt_id, session_id, turn_id, payload) do
    emit_prompt_event(session, session_id, turn_id, :notification, payload)
    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  defp handle_prompt_completion_malformed(session, prompt_id, session_id, turn_id, raw) do
    emit_prompt_event(session, session_id, turn_id, :malformed, raw, %{raw: raw})
    await_prompt_completion(session, prompt_id, session_id, turn_id)
  end

  defp respond_to_permission_request(port, request_id, params) do
    option_id = permission_option_id(params)

    CommandPort.send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "result" => %{
        "outcome" => %{
          "outcome" => "selected",
          "optionId" => option_id
        }
      }
    })
  end

  defp respond_method_not_found(port, request_id, method) do
    CommandPort.send_json(port, %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "error" => %{
        "code" => -32_601,
        "message" => "Unsupported ACP client method #{method}"
      }
    })
  end

  defp permission_option_id(%{"options" => options}) when is_list(options) do
    options
    |> Enum.find(fn option ->
      kind = option["kind"] || option[:kind]
      kind in ["allow_once", "allow_always", :allow_once, :allow_always]
    end)
    |> case do
      nil ->
        options
        |> List.first()
        |> option_id()

      option ->
        option_id(option)
    end
  end

  defp permission_option_id(_params), do: nil

  defp option_id(option) when is_map(option) do
    option["optionId"] || option[:optionId] || option["option_id"] || option[:option_id]
  end

  defp option_id(_option), do: nil

  defp session_capabilities(result) when is_map(result) do
    get_in(result, ["agentCapabilities", "sessionCapabilities"]) ||
      get_in(result, [:agentCapabilities, :sessionCapabilities]) ||
      %{}
  end

  defp session_capabilities(_result), do: %{}

  defp close_supported?(capabilities) when is_map(capabilities) do
    close_capability = capabilities["close"] || capabilities[:close]
    is_map(close_capability)
  end

  defp close_supported?(_capabilities), do: false

  defp emit_prompt_event(session, session_id, turn_id, event, payload, extra_payload \\ %{}) do
    emit_event(
      session,
      %{
        event: event,
        session_id: session_id,
        thread_id: session.session_id,
        turn_id: turn_id,
        payload: payload
      }
      |> Map.merge(extra_payload)
    )
  end

  defp composite_session_id(raw_session_id, turn_id) when is_binary(raw_session_id) and is_binary(turn_id) do
    "#{raw_session_id}-turn-#{turn_id}"
  end

  defp emit_event(session, payload) when is_map(payload) do
    session.on_event.(
      AgentBackend.normalize_runtime_event(
        @backend_name,
        Map.merge(session.metadata, Map.put_new(payload, :timestamp, DateTime.utc_now()))
      )
    )
  end
end

defmodule SymphonyElixir.AgentBackend.ClaudeCliStream do
  @moduledoc """
  Claude Code backend that runs `claude -p` in stream-json mode and resumes
  the same Claude session across logical Symphony turns.
  """

  @behaviour SymphonyElixir.AgentBackend

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.AgentBackend.CommandPort
  alias SymphonyElixir.Config

  @backend_name :claude_cli_stream

  @impl true
  def start_session(context, _opts) do
    backend_settings = Config.agent_backend_settings()

    initial_state = %{
      command: backend_settings.command,
      on_event: AgentBackend.value_from(context, :on_event) || fn _event -> :ok end,
      raw_session_id: nil,
      read_timeout_ms: backend_settings.read_timeout_ms,
      turn_timeout_ms: backend_settings.turn_timeout_ms,
      worker_host: AgentBackend.value_from(context, :worker_host),
      workspace: AgentBackend.value_from(context, :workspace_path)
    }

    Agent.start_link(fn -> initial_state end)
  end

  @impl true
  def run_turn(session_pid, turn, _opts) when is_pid(session_pid) do
    state = Agent.get(session_pid, & &1)
    command = claude_command(state.command, turn.prompt, state.raw_session_id)

    with {:ok, port_session} <- CommandPort.start(state.workspace, state.worker_host, command),
         result <- consume_stream(state, port_session, turn) do
      CommandPort.stop(port_session)
      finalize_turn(session_pid, result, turn)
    end
  end

  @impl true
  def stop_session(session_pid) when is_pid(session_pid) do
    Agent.stop(session_pid, :normal, 5_000)
  catch
    :exit, _reason -> :ok
  end

  def stop_session(_session), do: :ok

  defp consume_stream(state, port_session, turn) do
    turn_id = Integer.to_string(turn.turn_number)

    stream_loop(
      state,
      port_session,
      turn_id,
      %{
        composite_session_id: nil,
        emitted_session_started?: false,
        raw_session_id: state.raw_session_id,
        result_message: nil
      }
    )
  end

  defp stream_loop(state, port_session, turn_id, acc) do
    case CommandPort.receive_json(port_session.port, state.turn_timeout_ms) do
      {:ok, message, _pending_line} ->
        next_acc = handle_stream_message(state, port_session, turn_id, acc, message)
        stream_loop(state, port_session, turn_id, next_acc)

      {:malformed, raw, _pending_line} ->
        next_acc =
          if acc.result_message do
            acc
          else
            emit_event(state, port_session.metadata, acc, turn_id, %{
              event: :malformed,
              payload: raw,
              raw: raw
            })
          end

        stream_loop(state, port_session, turn_id, next_acc)

      {:error, {:port_exit, status}} ->
        {:port_exit, status, acc}

      {:error, :timeout} ->
        {:error, :turn_timeout, acc}

      {:error, reason} ->
        {:error, reason, acc}
    end
  end

  defp handle_stream_message(state, port_session, turn_id, acc, message) do
    raw_session_id = extract_session_id(message) || acc.raw_session_id
    composite_session_id = acc.composite_session_id || composite_session_id(raw_session_id, turn_id)

    acc =
      %{
        acc
        | raw_session_id: raw_session_id,
          composite_session_id: composite_session_id
      }

    acc =
      if raw_session_id && not acc.emitted_session_started? do
        emit_event(state, port_session.metadata, acc, turn_id, %{
          event: :session_started,
          payload: message
        })
      else
        acc
      end

    if acc.result_message do
      acc
    else
      case message_type(message) do
        "result" ->
          subtype = Map.get(message, "subtype")
          event = if subtype == "success", do: :turn_completed, else: :turn_failed

          emit_event(state, port_session.metadata, acc, turn_id, %{
            event: event,
            payload: message,
            usage: extract_usage(message)
          })
          |> Map.put(:result_message, message)

        _ ->
          emit_event(state, port_session.metadata, acc, turn_id, %{
            event: :notification,
            payload: message,
            usage: extract_usage(message)
          })
      end
    end
  end

  defp finalize_turn(session_pid, {:port_exit, status, %{result_message: result_message} = acc}, turn)
       when status in [0, nil] and is_map(result_message) do
    Agent.update(session_pid, fn state -> %{state | raw_session_id: acc.raw_session_id} end)

    case Map.get(result_message, "subtype") do
      "success" ->
        {:ok,
         %{
           backend: @backend_name,
           result: Map.get(result_message, "result"),
           session_id: acc.composite_session_id,
           thread_id: acc.raw_session_id,
           turn_id: Integer.to_string(turn.turn_number)
         }}

      subtype ->
        {:error, {:claude_result, subtype, result_message}}
    end
  end

  defp finalize_turn(_session_pid, {:port_exit, status, %{result_message: nil}}, _turn) do
    {:error, {:port_exit, status}}
  end

  defp finalize_turn(_session_pid, {:error, reason, _acc}, _turn), do: {:error, reason}

  defp emit_event(state, metadata, acc, turn_id, payload) when is_map(payload) do
    if acc.raw_session_id do
      state.on_event.(
        AgentBackend.normalize_runtime_event(
          @backend_name,
          Map.merge(metadata, %{
            event: payload.event,
            timestamp: DateTime.utc_now(),
            session_id: acc.composite_session_id,
            thread_id: acc.raw_session_id,
            turn_id: turn_id,
            payload: payload[:payload],
            raw: payload[:raw],
            usage: payload[:usage]
          })
        )
      )

      %{acc | emitted_session_started?: true}
    else
      acc
    end
  end

  defp claude_command(base_command, prompt, raw_session_id)
       when is_binary(base_command) and is_binary(prompt) do
    resume_arg =
      case raw_session_id do
        session_id when is_binary(session_id) and session_id != "" ->
          " --resume " <> CommandPort.shell_escape(session_id)

        _ ->
          ""
      end

    base_command <>
      " --print --output-format stream-json --verbose --include-partial-messages" <>
      resume_arg <>
      " " <> CommandPort.shell_escape(prompt)
  end

  defp composite_session_id(raw_session_id, turn_id)
       when is_binary(raw_session_id) and is_binary(turn_id) do
    "#{raw_session_id}-turn-#{turn_id}"
  end

  defp composite_session_id(_raw_session_id, _turn_id), do: nil

  defp message_type(message) when is_map(message) do
    Map.get(message, "type") || Map.get(message, :type)
  end

  defp extract_session_id(message) when is_map(message) do
    Map.get(message, "session_id") ||
      Map.get(message, :session_id) ||
      get_in(message, ["data", "session_id"]) ||
      get_in(message, [:data, :session_id])
  end

  defp extract_session_id(_message), do: nil

  defp extract_usage(message) when is_map(message) do
    Map.get(message, "usage") ||
      Map.get(message, :usage) ||
      get_in(message, ["message", "usage"]) ||
      get_in(message, [:message, :usage])
  end

  defp extract_usage(_message), do: nil
end

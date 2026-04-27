defmodule SymphonyElixir.AgentBackend.ClaudeCliStream do
  @moduledoc """
  Claude Code backend that runs `claude -p` in stream-json mode and resumes
  the same Claude session across logical Symphony turns.
  """

  require Logger

  @behaviour SymphonyElixir.AgentBackend

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.AgentBackend.CommandPort
  alias SymphonyElixir.Config

  @backend_name :claude_cli_stream
  @claude_log_env "SYMPHONY_CLAUDE_LOG_LEVEL"
  @claude_log_level_rank %{off: 0, info: 1, debug: 2, trace: 3}

  @impl true
  def start_session(context, _opts) do
    backend_settings = Config.agent_backend_settings()

    initial_state = %{
      command: backend_settings.command,
      on_event: AgentBackend.value_from(context, :on_event) || fn _event -> :ok end,
      claude_log_level: resolve_claude_log_level(),
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

    log_claude_message(state, :info, fn -> command end)

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
    end
  end

  defp handle_stream_message(state, port_session, turn_id, acc, message) do
    acc
    |> update_stream_session_ids(message, turn_id)
    |> maybe_emit_session_started(state, port_session.metadata, turn_id, message)
    |> maybe_emit_stream_message(state, port_session.metadata, turn_id, message)
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

  defp update_stream_session_ids(acc, message, turn_id) do
    raw_session_id = extract_session_id(message) || acc.raw_session_id
    composite_session_id = acc.composite_session_id || composite_session_id(raw_session_id, turn_id)

    %{
      acc
      | raw_session_id: raw_session_id,
        composite_session_id: composite_session_id
    }
  end

  defp maybe_emit_session_started(
         %{raw_session_id: nil} = acc,
         _state,
         _metadata,
         _turn_id,
         _message
       ) do
    acc
  end

  defp maybe_emit_session_started(
         %{emitted_session_started?: true} = acc,
         _state,
         _metadata,
         _turn_id,
         _message
       ) do
    acc
  end

  defp maybe_emit_session_started(acc, state, metadata, turn_id, message) do
    emit_event(state, metadata, acc, turn_id, %{
      event: :session_started,
      payload: message
    })
  end

  defp maybe_emit_stream_message(
         %{result_message: result_message} = acc,
         _state,
         _metadata,
         _turn_id,
         _message
       )
       when not is_nil(result_message) do
    acc
  end

  defp maybe_emit_stream_message(acc, state, metadata, turn_id, message) do
    case message_type(message) do
      "result" ->
        emit_stream_result(state, metadata, acc, turn_id, message)

      _ ->
        emit_stream_notification(state, metadata, acc, turn_id, message)
    end
  end

  defp emit_stream_result(state, metadata, acc, turn_id, message) do
    subtype = Map.get(message, "subtype")
    event = if subtype == "success", do: :turn_completed, else: :turn_failed

    emit_event(state, metadata, acc, turn_id, %{
      event: event,
      payload: message,
      usage: extract_usage(message)
    })
    |> Map.put(:result_message, message)
  end

  defp emit_stream_notification(state, metadata, acc, turn_id, message) do
    emit_event(state, metadata, acc, turn_id, %{
      event: :notification,
      payload: message,
      usage: extract_usage(message)
    })
  end

  defp emit_event(state, metadata, acc, turn_id, payload) when is_map(payload) do
    if acc.raw_session_id do
      log_claude_event(state, payload, acc, turn_id)

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

  defp extract_usage(message) when is_map(message) do
    Map.get(message, "usage") ||
      Map.get(message, :usage) ||
      get_in(message, ["message", "usage"]) ||
      get_in(message, [:message, :usage])
  end

  defp resolve_claude_log_level do
    System.get_env(@claude_log_env)
    |> normalize_claude_log_level()
  end

  defp normalize_claude_log_level(nil), do: :info

  defp normalize_claude_log_level(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "off" -> :off
      "info" -> :info
      "debug" -> :debug
      "trace" -> :trace
      _ -> :info
    end
  end

  defp log_claude_event(state, payload, acc, turn_id) do
    case claude_event_log_level(payload.event) do
      required_level ->
        log_claude_message(state, required_level, fn ->
          claude_event_message(state, payload, acc, turn_id)
        end)
    end
  end

  defp claude_event_log_level(:session_started), do: :info
  defp claude_event_log_level(:turn_completed), do: :info
  defp claude_event_log_level(:turn_failed), do: :info
  defp claude_event_log_level(:notification), do: :debug
  defp claude_event_log_level(:malformed), do: :debug

  defp claude_event_message(state, payload, acc, turn_id) do
    session_id = acc.composite_session_id || acc.raw_session_id || "unknown"
    thread_id = acc.raw_session_id || "unknown"

    base_message = claude_event_base_message(payload.event, session_id, thread_id, turn_id, payload)

    if state.claude_log_level == :trace do
      base_message <> " payload=#{inspect(payload[:payload], limit: 10, printable_limit: 120)}"
    else
      base_message
    end
  end

  defp claude_event_base_message(:session_started, session_id, thread_id, turn_id, _payload) do
    "Claude session started session_id=#{session_id} thread_id=#{thread_id} turn_id=#{turn_id}"
  end

  defp claude_event_base_message(:notification, session_id, thread_id, turn_id, payload) do
    "Claude notification session_id=#{session_id} thread_id=#{thread_id} turn_id=#{turn_id} type=#{inspect(message_type(payload[:payload]))}"
  end

  defp claude_event_base_message(:turn_completed, session_id, thread_id, turn_id, _payload) do
    "Claude turn completed session_id=#{session_id} thread_id=#{thread_id} turn_id=#{turn_id}"
  end

  defp claude_event_base_message(:turn_failed, session_id, thread_id, turn_id, payload) do
    "Claude turn failed session_id=#{session_id} thread_id=#{thread_id} turn_id=#{turn_id} subtype=#{inspect(Map.get(payload[:payload], "subtype"))}"
  end

  defp claude_event_base_message(:malformed, session_id, thread_id, turn_id, _payload) do
    "Claude malformed payload session_id=#{session_id} thread_id=#{thread_id} turn_id=#{turn_id}"
  end

  defp log_claude_message(state, required_level, message_fun) when is_function(message_fun, 0) do
    if claude_log_level_enabled?(state.claude_log_level, required_level) do
      log_message = message_fun.()

      case logger_level_for_claude_level(required_level) do
        :debug -> Logger.debug(log_message)
        _ -> Logger.info(log_message)
      end
    end
  end

  defp claude_log_level_enabled?(current_level, required_level) do
    claude_log_level_rank(current_level) >= claude_log_level_rank(required_level)
  end

  defp claude_log_level_rank(level), do: Map.get(@claude_log_level_rank, level, 1)

  defp logger_level_for_claude_level(:debug), do: :debug
  defp logger_level_for_claude_level(:info), do: :info
end

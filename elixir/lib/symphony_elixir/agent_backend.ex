defmodule SymphonyElixir.AgentBackend do
  @moduledoc """
  Behaviour and helpers for backend-neutral agent execution.

  A backend owns the logical session handle and emits normalized runtime
  events. AgentRunner builds backend context/turn maps and forwards those
  events to the orchestrator.
  """

  @typedoc "Backend-owned execution context."
  @type context :: %{
          required(:workspace_path) => Path.t(),
          required(:issue_id) => String.t(),
          required(:issue_identifier) => String.t(),
          required(:issue_title) => String.t(),
          optional(:worker_host) => String.t() | nil,
          optional(:on_event) => (runtime_event() -> any())
        }

  @typedoc "Rendered prompt and turn metadata passed to a backend."
  @type turn :: %{
          required(:prompt) => String.t(),
          required(:turn_number) => pos_integer(),
          required(:max_turns) => pos_integer()
        }

  @typedoc "Opaque backend-owned session handle."
  @type session :: map()

  @typedoc "Backend turn result payload."
  @type turn_result :: map()

  @typedoc "Normalized runtime event emitted by a backend."
  @type runtime_event :: map()

  @callback start_session(context(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback run_turn(session(), turn(), keyword()) :: {:ok, turn_result()} | {:error, term()}
  @callback stop_session(session()) :: :ok

  @spec normalize_event(atom() | String.t(), map(), map() | keyword()) :: runtime_event()
  def normalize_event(backend, event, metadata \\ %{}) when is_map(event) do
    metadata = normalize_metadata(metadata)
    backend = normalize_backend(backend)

    event
    |> Map.merge(metadata)
    |> Map.put(:backend, backend)
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> normalize_pid_aliases(backend)
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_metadata), do: %{}

  defp normalize_backend("codex_app_server"), do: :codex_app_server
  defp normalize_backend(backend) when is_atom(backend), do: backend
  defp normalize_backend(backend), do: backend

  defp normalize_pid_aliases(event, :codex_app_server) do
    event
    |> ensure_worker_pid()
    |> ensure_codex_app_server_pid()
  end

  defp normalize_pid_aliases(event, _backend) do
    ensure_worker_pid(event)
  end

  defp ensure_worker_pid(event) do
    case get_value(event, :worker_pid) do
      nil ->
        case get_value(event, :codex_app_server_pid) do
          nil -> event
          pid -> Map.put(event, :worker_pid, pid)
        end

      _worker_pid ->
        event
    end
  end

  defp ensure_codex_app_server_pid(event) do
    case get_value(event, :codex_app_server_pid) do
      nil ->
        case get_value(event, :worker_pid) do
          nil -> event
          pid -> Map.put(event, :codex_app_server_pid, pid)
        end

      _pid ->
        event
    end
  end

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end

defmodule SymphonyElixir.AgentBackend do
  @moduledoc """
  Runtime contract for logical agent backends.

  Backends own session state, run logical turns, stop sessions, and emit
  normalized runtime events back to the orchestrator.
  """

  @typedoc "Backend-independent execution context supplied when a session starts."
  @type context :: map()

  @typedoc "Opaque backend-owned session handle."
  @type session :: term()

  @typedoc "Backend turn request."
  @type turn :: map()

  @typedoc "Backend turn result."
  @type turn_result :: map()

  @typedoc "Normalized runtime event emitted by a backend."
  @type event :: map()

  @callback start_session(context(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback run_turn(session(), turn(), keyword()) :: {:ok, turn_result()} | {:error, term()}
  @callback stop_session(session()) :: :ok

  @spec normalize_runtime_event(atom() | module() | String.t() | nil, map()) :: map()
  def normalize_runtime_event(backend, message) when is_map(message) do
    backend_name = normalize_backend_name(backend)
    timestamp = value_from(message, :timestamp) || DateTime.utc_now()
    worker_pid = value_from(message, :worker_pid) || value_from(message, :codex_app_server_pid)

    message
    |> Map.put(:backend, backend_name)
    |> put_standard_field(:event)
    |> put_standard_field(:timestamp, timestamp)
    |> put_standard_field(:session_id)
    |> put_standard_field(:thread_id)
    |> put_standard_field(:turn_id)
    |> put_standard_field(:worker_pid, worker_pid)
    |> put_standard_field(:usage)
    |> put_standard_field(:rate_limits)
    |> put_standard_field(:payload)
    |> put_standard_field(:raw)
    |> put_standard_field(:codex_app_server_pid)
  end

  def normalize_runtime_event(_backend, message), do: message

  @spec normalize_backend_name(atom() | module() | String.t() | nil) :: atom() | String.t()
  def normalize_backend_name(nil), do: :unknown_backend

  def normalize_backend_name(backend) when is_atom(backend) do
    case Atom.to_string(backend) do
      "Elixir." <> _ ->
        backend
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> backend_name_atom_or_string()

      _ ->
        backend
    end
  end

  def normalize_backend_name(backend) when is_binary(backend), do: backend

  def normalize_backend_name(backend), do: backend

  @doc false
  @spec normalize_work_item(map()) :: map()
  def normalize_work_item(work_item) when is_map(work_item) do
    %{
      id: value_from(work_item, :id),
      identifier: value_from(work_item, :identifier),
      title: value_from(work_item, :title),
      description: value_from(work_item, :description)
    }
  end

  @doc false
  @spec value_from(map(), atom()) :: term()
  def value_from(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp put_standard_field(map, key), do: put_standard_field(map, key, value_from(map, key))

  defp put_standard_field(map, _key, nil), do: map

  defp put_standard_field(map, key, value), do: Map.put_new(map, key, value)

  defp backend_name_atom_or_string(name) when is_binary(name) do
    # credo:disable-for-next-line
    try do
      String.to_existing_atom(name)
    rescue
      ArgumentError -> name
    end
  end
end

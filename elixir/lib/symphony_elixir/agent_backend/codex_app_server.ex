defmodule SymphonyElixir.AgentBackend.CodexAppServer do
  @moduledoc """
  Default compatibility backend that delegates to `SymphonyElixir.Codex.AppServer`.
  """

  @behaviour SymphonyElixir.AgentBackend

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.Codex.AppServer

  @backend_name :codex_app_server

  @spec start_session(AgentBackend.context(), keyword()) ::
          {:ok, AgentBackend.session()} | {:error, term()}
  def start_session(context, opts \\ []) when is_map(context) do
    workspace_path = context_value(context, :workspace_path)
    worker_host = context_value(context, :worker_host) || Keyword.get(opts, :worker_host)
    on_event = context_value(context, :on_event) || Keyword.get(opts, :on_event) || default_on_event()
    work_item = context_value(context, :work_item) || %{}

    case workspace_path do
      path when is_binary(path) and path != "" ->
        with {:ok, app_session} <- AppServer.start_session(path, worker_host: worker_host) do
          {:ok,
           %{
             backend: @backend_name,
             app_session: app_session,
             context: context,
             on_event: on_event,
             work_item: work_item,
             worker_host: worker_host,
             workspace_path: path
           }}
        end

      _ ->
        {:error, :missing_workspace_path}
    end
  end

  @spec run_turn(AgentBackend.session(), AgentBackend.turn(), keyword()) ::
          {:ok, AgentBackend.turn_result()} | {:error, term()}
  def run_turn(%{app_session: app_session, on_event: on_event, work_item: work_item}, turn, opts)
      when is_map(turn) do
    prompt = turn_value(turn, :prompt)
    tool_executor = Keyword.get(opts, :tool_executor)
    work_item = normalize_work_item(work_item || turn_value(turn, :work_item) || %{})

    on_message = fn message ->
      on_event.(AgentBackend.normalize_runtime_event(@backend_name, message))
    end

    run_opts =
      []
      |> maybe_put_opt(:on_message, on_message)
      |> maybe_put_opt(:tool_executor, tool_executor)

    case AppServer.run_turn(app_session, prompt, work_item, run_opts) do
      {:ok, result} ->
        {:ok, Map.put(result, :backend, @backend_name)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run_turn(_session, _turn, _opts), do: {:error, :invalid_session}

  @spec stop_session(AgentBackend.session()) :: :ok
  def stop_session(%{app_session: app_session}) do
    AppServer.stop_session(app_session)
  end

  def stop_session(_session), do: :ok

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp context_value(context, key) when is_map(context) do
    Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end

  defp turn_value(turn, key) when is_map(turn) do
    Map.get(turn, key) || Map.get(turn, Atom.to_string(key))
  end

  defp normalize_work_item(work_item) when is_map(work_item) do
    %{
      id: value_from(work_item, :id),
      identifier: value_from(work_item, :identifier),
      title: value_from(work_item, :title),
      description: value_from(work_item, :description)
    }
  end

  defp value_from(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp default_on_event do
    fn _message -> :ok end
  end
end

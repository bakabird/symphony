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
    workspace_path = AgentBackend.value_from(context, :workspace_path)
    worker_host = AgentBackend.value_from(context, :worker_host) || Keyword.get(opts, :worker_host)
    on_event = AgentBackend.value_from(context, :on_event) || Keyword.get(opts, :on_event) || default_on_event()
    work_item = AgentBackend.value_from(context, :work_item) || %{}

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
    prompt = AgentBackend.value_from(turn, :prompt)
    tool_executor = Keyword.get(opts, :tool_executor)
    work_item = AgentBackend.normalize_work_item(work_item || AgentBackend.value_from(turn, :work_item) || %{})

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

  defp default_on_event do
    fn _message -> :ok end
  end
end

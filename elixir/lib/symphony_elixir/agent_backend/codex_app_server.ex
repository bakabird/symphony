defmodule SymphonyElixir.AgentBackend.CodexAppServer do
  @moduledoc """
  Compatibility backend that delegates to `SymphonyElixir.Codex.AppServer`.

  The wrapper keeps the existing Codex protocol semantics intact while
  normalizing runtime events for backend-neutral orchestration.
  """

  @behaviour SymphonyElixir.AgentBackend

  alias SymphonyElixir.{AgentBackend, Codex.AppServer}

  @impl true
  def start_session(context, opts) when is_map(context) do
    workspace_path = Map.fetch!(context, :workspace_path)
    worker_host = Map.get(context, :worker_host)

    with {:ok, session} <- AppServer.start_session(workspace_path, Keyword.put(opts, :worker_host, worker_host)) do
      {:ok,
       Map.merge(session, %{
         backend_context: backend_context(context)
       })}
    end
  end

  @impl true
  def run_turn(%{backend_context: backend_context} = session, %{prompt: prompt}, opts)
      when is_binary(prompt) do
    issue = issue_from_context(backend_context)
    on_event = Map.get(backend_context, :on_event)

    AppServer.run_turn(
      session,
      prompt,
      issue,
      Keyword.put(opts, :on_message, &forward_event(on_event, backend_context, &1))
    )
  end

  @impl true
  def stop_session(session) when is_map(session) do
    AppServer.stop_session(session)
  end

  defp backend_context(context) do
    %{
      issue_id: Map.fetch!(context, :issue_id),
      issue_identifier: Map.fetch!(context, :issue_identifier),
      issue_title: Map.fetch!(context, :issue_title),
      on_event: Map.get(context, :on_event),
      worker_host: Map.get(context, :worker_host),
      workspace_path: Map.fetch!(context, :workspace_path)
    }
  end

  defp issue_from_context(backend_context) do
    %{
      id: backend_context.issue_id,
      identifier: backend_context.issue_identifier,
      title: backend_context.issue_title
    }
  end

  defp forward_event(on_event, backend_context, message) when is_function(on_event, 1) and is_map(message) do
    on_event.(
      AgentBackend.normalize_event(
        :codex_app_server,
        message,
        normalized_event_metadata(backend_context)
      )
    )

    :ok
  end

  defp forward_event(_on_event, _backend_context, _message), do: :ok

  defp normalized_event_metadata(backend_context) do
    %{
      issue_id: backend_context.issue_id,
      issue_identifier: backend_context.issue_identifier,
      issue_title: backend_context.issue_title,
      worker_host: backend_context.worker_host,
      workspace_path: backend_context.workspace_path
    }
  end
end

defmodule SymphonyElixir.AgentBackend.Resolver do
  @moduledoc """
  Resolves the backend module for an agent run.

  The current default is the Codex app-server compatibility wrapper. Tests
  may override the backend by passing `backend:` to AgentRunner.
  """

  alias SymphonyElixir.AgentBackend.CodexAppServer

  @spec resolve(keyword()) :: module()
  def resolve(opts \\ []) do
    case Keyword.get(opts, :backend) do
      nil -> CodexAppServer
      :codex_app_server -> CodexAppServer
      backend when is_atom(backend) -> backend
      backend -> backend
    end
  end
end

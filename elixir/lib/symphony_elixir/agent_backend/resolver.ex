defmodule SymphonyElixir.AgentBackend.Resolver do
  @moduledoc """
  Resolves the backend module used by AgentRunner.
  """

  alias SymphonyElixir.AgentBackend.CodexAppServer

  @spec resolve(keyword()) :: module()
  def resolve(opts \\ []) when is_list(opts) do
    Keyword.get(opts, :backend) ||
      Keyword.get(opts, :backend_module) ||
      CodexAppServer
  end
end

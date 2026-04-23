defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single Linear issue in its workspace with a resolved agent backend.
  """

  require Logger
  alias SymphonyElixir.AgentBackend.Resolver
  alias SymphonyElixir.{Config, Linear.Issue, PromptBuilder, Tracker, Workspace}

  @type worker_host :: String.t() | nil

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, codex_update_recipient \\ nil, opts \\ []) do
    # The orchestrator owns host retries so one worker lifetime never hops machines.
    worker_host = selected_worker_host(Keyword.get(opts, :worker_host), Config.settings!().worker.ssh_hosts)

    Logger.info("Starting agent run for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
    Logger.info("Starting worker attempt for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case Workspace.create_for_issue(issue, worker_host) do
      {:ok, workspace} ->
        send_worker_runtime_info(codex_update_recipient, issue, worker_host, workspace)

        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host) do
            run_backend_turns(workspace, issue, codex_update_recipient, opts, worker_host)
          end
        after
          Workspace.run_after_run_hook(workspace, issue, worker_host)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp agent_message_handler(recipient, issue) do
    fn message ->
      send_agent_update(recipient, issue, message)
    end
  end

  defp send_agent_update(recipient, %Issue{id: issue_id}, message)
       when is_binary(issue_id) and is_pid(recipient) do
    send(recipient, {:agent_worker_update, issue_id, message})
    :ok
  end

  defp send_agent_update(_recipient, _issue, _message), do: :ok

  defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       %{
         worker_host: worker_host,
         workspace_path: workspace
       }}
    )

    :ok
  end

  defp send_worker_runtime_info(_recipient, _issue, _worker_host, _workspace), do: :ok

  defp run_backend_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
    max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.max_turns)
    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)
    backend_module = Resolver.resolve(opts) |> ensure_backend_module!()
    backend_opts = Keyword.get(opts, :backend_opts, []) |> List.wrap()
    on_event = agent_message_handler(codex_update_recipient, issue)
    backend_context = build_backend_context(issue, workspace, worker_host, on_event)

    with {:ok, session} <- backend_module.start_session(backend_context, backend_opts) do
      try do
        run_context = %{
          backend_module: backend_module,
          backend_opts: backend_opts,
          issue: issue,
          issue_state_fetcher: issue_state_fetcher,
          opts: opts,
          session: session,
          workspace: workspace,
          max_turns: max_turns
        }

        do_run_backend_turns(run_context, 1)
      after
        backend_module.stop_session(session)
      end
    end
  end

  defp ensure_backend_module!(backend_module) when is_atom(backend_module) do
    if backend_module_valid?(backend_module) do
      backend_module
    else
      raise ArgumentError,
            "Resolved backend #{inspect(backend_module)} does not implement AgentBackend callbacks"
    end
  end

  defp ensure_backend_module!(backend_module) do
    raise ArgumentError,
          "Resolved backend #{inspect(backend_module)} does not implement AgentBackend callbacks"
  end

  defp backend_module_valid?(backend_module) do
    function_exported?(backend_module, :start_session, 2) and
      function_exported?(backend_module, :run_turn, 3) and
      function_exported?(backend_module, :stop_session, 1)
  end

  defp do_run_backend_turns(context, turn_number) do
    %{
      backend_module: backend_module,
      backend_opts: backend_opts,
      issue: issue,
      issue_state_fetcher: issue_state_fetcher,
      opts: opts,
      session: session,
      workspace: workspace,
      max_turns: max_turns
    } = context

    turn = build_turn(issue, opts, turn_number, max_turns)

    with {:ok, turn_session} <- backend_module.run_turn(session, turn, backend_opts) do
      completion_message =
        [
          "Completed agent run for #{issue_context(issue)}",
          "session_id=#{turn_session[:session_id]}",
          "workspace=#{workspace}",
          "turn=#{turn_number}/#{max_turns}"
        ]
        |> Enum.join(" ")

      Logger.info(completion_message)

      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          continuation_message =
            [
              "Continuing agent run for #{issue_context(refreshed_issue)}",
              "after normal turn completion",
              "turn=#{turn_number}/#{max_turns}"
            ]
            |> Enum.join(" ")

          Logger.info(continuation_message)

          do_run_backend_turns(%{context | issue: refreshed_issue}, turn_number + 1)

        {:continue, refreshed_issue} ->
          max_turns_message =
            [
              "Reached agent.max_turns for #{issue_context(refreshed_issue)}",
              "with issue still active",
              "returning control to orchestrator"
            ]
            |> Enum.join(" ")

          Logger.info(max_turns_message)

          :ok

        {:done, _refreshed_issue} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_turn(issue, opts, turn_number, max_turns) do
    %{
      prompt: build_turn_prompt(issue, opts, turn_number, max_turns),
      turn_number: turn_number,
      max_turns: max_turns,
      work_item: build_work_item(issue)
    }
  end

  defp build_turn_prompt(issue, opts, 1, _max_turns), do: PromptBuilder.build_prompt(issue, opts)

  defp build_turn_prompt(_issue, _opts, turn_number, max_turns) do
    """
    Continuation guidance:

    - The previous agent turn completed normally, but the Linear issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp build_backend_context(issue, workspace, worker_host, on_event) do
    %{
      on_event: on_event,
      work_item: build_work_item(issue),
      worker_host: worker_host,
      workspace_path: workspace
    }
  end

  defp build_work_item(%Issue{id: issue_id, identifier: identifier, title: title, description: description}) do
    %{
      id: issue_id,
      identifier: identifier,
      title: title,
      description: description
    }
  end

  defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp selected_worker_host(nil, []), do: nil

  defp selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  defp worker_host_for_log(nil), do: "local"
  defp worker_host_for_log(worker_host), do: worker_host

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end
end

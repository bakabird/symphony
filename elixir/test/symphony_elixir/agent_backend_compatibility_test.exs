defmodule SymphonyElixir.AgentBackendCompatibilityTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend.CodexAppServer

  test "agent runner forwards neutral runtime updates through a fake backend and stops the session" do
    test_pid = self()
    issue_id = "issue-fake-backend"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-900",
      title: "Fake backend test",
      description: "Exercise AgentRunner with a fake backend",
      state: "In Progress",
      url: "https://example.org/issues/MT-900"
    }

    state_fetcher = fn [_issue_id] ->
      attempt = Process.get(:agent_backend_state_fetch_count, 0) + 1
      Process.put(:agent_backend_state_fetch_count, attempt)

      state =
        if attempt == 1 do
          "In Progress"
        else
          "Done"
        end

      {:ok, [%{issue | state: state}]}
    end

    assert :ok =
             AgentRunner.run(issue, test_pid,
               backend: SymphonyElixir.AgentBackendCompatibilityTest.FakeBackend,
               test_pid: test_pid,
               issue_state_fetcher: state_fetcher
             )

    assert_receive {:fake_backend_start_session, context}
    assert context.issue_id == issue_id
    assert context.issue_identifier == issue.identifier
    assert context.issue_title == issue.title
    assert is_function(context.on_event, 1)

    assert_receive {:fake_backend_run_turn, 1, %{prompt: first_prompt, turn_number: 1, max_turns: 20}}
    assert first_prompt =~ "You are an agent for this repository."

    assert_receive {:agent_worker_update, ^issue_id, %{backend: :fake_backend, event: :session_started}}
    assert_receive {:agent_worker_update, ^issue_id, %{backend: :fake_backend, event: :turn_completed}}

    assert_receive {:fake_backend_run_turn, 2, %{prompt: second_prompt, turn_number: 2, max_turns: 20}}
    assert second_prompt =~ "Continuation guidance:"
    assert second_prompt =~ "previous agent turn"

    assert_receive {:agent_worker_update, ^issue_id, %{backend: :fake_backend, event: :session_started}}
    assert_receive {:agent_worker_update, ^issue_id, %{backend: :fake_backend, event: :turn_completed}}
    assert_receive {:fake_backend_stop_session, session}
    assert session.session_id == "fake-session"
  end

  test "codex compatibility backend delegates to app server and normalizes callback events" do
    test_pid = self()

    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-codex-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-901")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-codex"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-codex"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server"
      )

      context = %{
        workspace_path: workspace,
        worker_host: nil,
        issue_id: "issue-codex-wrapper",
        issue_identifier: "MT-901",
        issue_title: "Codex wrapper test",
        on_event: fn message -> send(test_pid, {:backend_event, message}) end
      }

      {:ok, session} = CodexAppServer.start_session(context, test_pid: test_pid)
      assert is_map(session)
      assert is_map(session.backend_context)
      assert session.backend_context.issue_id == context.issue_id

      {:ok, result} =
        CodexAppServer.run_turn(
          session,
          %{prompt: "hello", turn_number: 1, max_turns: 1},
          test_pid: test_pid
        )

      assert result.session_id == "thread-codex-turn-codex"
      assert_receive {:backend_event, %{backend: :codex_app_server, event: :session_started, worker_pid: worker_pid}}
      assert is_binary(worker_pid)
      assert_receive {:backend_event, %{backend: :codex_app_server, event: :turn_completed}}

      assert :ok = CodexAppServer.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end

  test "orchestrator accepts agent-neutral and legacy worker updates" do
    issue_id = "issue-orchestrator-neutral"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-902",
      title: "Orchestrator test",
      description: "Accept agent-neutral updates",
      state: "In Progress",
      url: "https://example.org/issues/MT-902"
    }

    orchestrator_name = Module.concat(__MODULE__, :NeutralOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      turn_count: 0,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      codex_app_server_pid: nil,
      codex_input_tokens: 0,
      codex_output_tokens: 0,
      codex_total_tokens: 0,
      codex_last_reported_input_tokens: 0,
      codex_last_reported_output_tokens: 0,
      codex_last_reported_total_tokens: 0,
      started_at: DateTime.utc_now()
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    now = DateTime.utc_now()

    send(
      pid,
      {:agent_worker_update, issue_id,
       %{
         event: :session_started,
         session_id: "thread-agent-turn-agent",
         timestamp: now
       }}
    )

    send(
      pid,
      {:codex_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "thread/tokenUsage/updated",
           "params" => %{
             "tokenUsage" => %{
               "total" => %{"inputTokens" => 3, "outputTokens" => 2, "totalTokens" => 5}
             }
           }
         },
         timestamp: now,
         codex_app_server_pid: "4321"
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [snapshot_entry]} = snapshot
    assert snapshot_entry.session_id == "thread-agent-turn-agent"
    assert snapshot_entry.turn_count == 1
    assert snapshot_entry.codex_app_server_pid == "4321"
    assert snapshot_entry.codex_input_tokens == 3
    assert snapshot_entry.codex_output_tokens == 2
    assert snapshot_entry.codex_total_tokens == 5
  end

  defmodule FakeBackend do
    @behaviour SymphonyElixir.AgentBackend

    alias SymphonyElixir.AgentBackend

    @impl true
    def start_session(context, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:fake_backend_start_session, context})

      {:ok,
       %{
         session_id: "fake-session",
         test_pid: test_pid,
         context: context
       }}
    end

    @impl true
    def run_turn(session, turn, _opts) do
      send(session.test_pid, {:fake_backend_run_turn, turn.turn_number, turn})

      session.context.on_event.(
        AgentBackend.normalize_event(
          :fake_backend,
          %{
            event: :session_started,
            session_id: session.session_id,
            timestamp: DateTime.utc_now()
          },
          %{backend_session: session.session_id}
        )
      )

      session.context.on_event.(
        AgentBackend.normalize_event(
          :fake_backend,
          %{
            event: :turn_completed,
            session_id: session.session_id,
            timestamp: DateTime.utc_now()
          },
          %{backend_session: session.session_id}
        )
      )

      {:ok, %{session_id: session.session_id, turn_id: "fake-turn-#{turn.turn_number}"}}
    end

    @impl true
    def stop_session(session) do
      send(session.test_pid, {:fake_backend_stop_session, session})
      :ok
    end
  end
end

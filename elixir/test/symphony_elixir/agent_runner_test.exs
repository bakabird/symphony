defmodule SymphonyElixir.AgentRunnerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend

  defmodule FakeBackend do
    @behaviour AgentBackend

    alias SymphonyElixir.AgentBackend

    def start_session(context, opts) do
      observer = Keyword.fetch!(opts, :observer)
      send(observer, {:fake_backend_start_session, context, opts})

      {:ok,
       %{
         context: context,
         observer: observer
       }}
    end

    def run_turn(%{context: context, observer: observer} = _session, turn, opts) do
      send(observer, {:fake_backend_run_turn, turn.turn_number, turn, opts})
      fail_turn_number = Keyword.get(opts, :fail_turn_number)
      turn_number = turn.turn_number

      event =
        AgentBackend.normalize_runtime_event(__MODULE__, %{
          event: if(turn.turn_number == 1, do: :session_started, else: :notification),
          timestamp: DateTime.utc_now(),
          session_id: "fake-session-#{turn.turn_number}",
          thread_id: "fake-thread",
          turn_id: "fake-turn-#{turn.turn_number}",
          codex_app_server_pid: "4242",
          payload: %{turn_number: turn.turn_number},
          raw: "fake raw #{turn.turn_number}"
        })

      context.on_event.(event)

      case fail_turn_number do
        ^turn_number ->
          {:error, {:fake_backend_failed, turn.turn_number}}

        _ ->
          {:ok,
           %{
             backend: :fake_backend,
             result: :ok,
             session_id: "fake-session-#{turn.turn_number}",
             thread_id: "fake-thread",
             turn_id: "fake-turn-#{turn.turn_number}"
           }}
      end
    end

    def stop_session(%{observer: observer} = session) do
      send(observer, {:fake_backend_stop_session, session})
      :ok
    end

    def stop_session(_session), do: :ok
  end

  test "agent runner resolves backend override, forwards updates, continues, and stops session" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-backend-override-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_id = "issue-backend-override"
      issue_identifier = "MT-424"
      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        title: "Backend override",
        description: "Exercise a custom backend",
        state: "In Progress",
        url: "https://example.org/issues/MT-424",
        labels: []
      }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        max_turns: 3
      )

      Process.delete(:fake_backend_state_fetches)
      observer = self()

      state_fetcher = fn [_issue_id] ->
        next_count = Process.get(:fake_backend_state_fetches, 0) + 1
        Process.put(:fake_backend_state_fetches, next_count)

        state =
          case next_count do
            1 -> "In Progress"
            _ -> "Done"
          end

        {:ok, [%Issue{issue | state: state}]}
      end

      assert :ok =
               AgentRunner.run(
                 issue,
                 observer,
                 backend: FakeBackend,
                 backend_opts: [observer: observer],
                 issue_state_fetcher: state_fetcher,
                 max_turns: 3
               )

      assert_receive {:fake_backend_start_session, context, start_opts}
      assert Keyword.get(start_opts, :observer) == observer
      assert String.ends_with?(context.workspace_path, "/workspaces/#{issue_identifier}")
      assert context.worker_host == nil
      assert context.work_item == %{
                 id: issue_id,
                 identifier: issue_identifier,
                 title: issue.title,
                 description: issue.description
               }

      assert_receive {:fake_backend_run_turn, 1, turn_1, run_opts_1}
      assert Keyword.get(run_opts_1, :observer) == observer
      assert turn_1.turn_number == 1
      assert turn_1.max_turns == 3
      assert turn_1.work_item.identifier == issue_identifier
      assert turn_1.prompt =~ "You are an agent for this repository."

      assert_receive {:agent_worker_update, ^issue_id, update_1}
      assert update_1.backend == :fake_backend
      assert update_1.event == :session_started
      assert update_1.session_id == "fake-session-1"
      assert update_1.thread_id == "fake-thread"
      assert update_1.turn_id == "fake-turn-1"
      assert update_1.payload == %{turn_number: 1}
      assert update_1.raw == "fake raw 1"
      assert update_1.codex_app_server_pid == "4242"
      assert update_1.worker_pid == "4242"

      assert_receive {:fake_backend_run_turn, 2, turn_2, run_opts_2}
      assert Keyword.get(run_opts_2, :observer) == observer
      assert turn_2.turn_number == 2
      assert turn_2.max_turns == 3
      assert turn_2.prompt =~ "Continuation guidance:"
      assert turn_2.prompt =~ "previous agent turn"
      assert turn_2.work_item.identifier == issue_identifier

      assert_receive {:agent_worker_update, ^issue_id, update_2}
      assert update_2.backend == :fake_backend
      assert update_2.event == :notification
      assert update_2.session_id == "fake-session-2"
      assert update_2.thread_id == "fake-thread"
      assert update_2.turn_id == "fake-turn-2"

      assert_receive {:fake_backend_stop_session, session}
      assert session.context.work_item.identifier == issue_identifier
      assert Process.get(:fake_backend_state_fetches) == 2
    after
      Process.delete(:fake_backend_state_fetches)
      File.rm_rf(test_root)
    end
  end

  test "agent runner stops the backend session when the backend fails" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-backend-failure-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_id = "issue-backend-failure"
      issue_identifier = "MT-425"
      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        title: "Backend failure",
        description: "Exercise backend failure cleanup",
        state: "In Progress",
        url: "https://example.org/issues/MT-425",
        labels: []
      }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root
      )

      observer = self()

      assert_raise RuntimeError, ~r/Agent run failed/, fn ->
        AgentRunner.run(
          issue,
          observer,
          backend: FakeBackend,
          backend_opts: [observer: observer, fail_turn_number: 1]
        )
      end

      assert_receive {:fake_backend_start_session, context, start_opts}
      assert Keyword.get(start_opts, :observer) == observer
      assert context.work_item.identifier == issue_identifier

      assert_receive {:fake_backend_run_turn, 1, turn, run_opts}
      assert Keyword.get(run_opts, :observer) == observer
      assert turn.turn_number == 1

      assert_receive {:agent_worker_update, ^issue_id, update}
      assert update.backend == :fake_backend
      assert update.event == :session_started

      assert_receive {:fake_backend_stop_session, session}
      assert session.context.work_item.identifier == issue_identifier
    after
      File.rm_rf(test_root)
    end
  end
end

defmodule SymphonyElixir.AgentBackend.CodexAppServerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.AgentBackend.CodexAppServer

  test "normalize_runtime_event preserves codex fields and adds backend metadata" do
    timestamp = DateTime.utc_now()

    event =
      AgentBackend.normalize_runtime_event(CodexAppServer, %{
        event: :notification,
        timestamp: timestamp,
        session_id: "thread-1-turn-1",
        thread_id: "thread-1",
        turn_id: "turn-1",
        codex_app_server_pid: "1234",
        payload: %{"method" => "turn/completed"},
        raw: ~s({"method":"turn/completed"})
      })

    assert event.backend == :codex_app_server
    assert event.event == :notification
    assert event.timestamp == timestamp
    assert event.session_id == "thread-1-turn-1"
    assert event.thread_id == "thread-1"
    assert event.turn_id == "turn-1"
    assert event.worker_pid == "1234"
    assert event.codex_app_server_pid == "1234"
    assert event.payload == %{"method" => "turn/completed"}
    assert event.raw == ~s({"method":"turn/completed"})
  end

  test "codex app-server backend delegates session lifecycle and normalizes events" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-codex-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-451")
      codex_binary = Path.join(test_root, "fake-codex")
      parent = self()

      File.mkdir_p!(workspace)
      File.write!(codex_binary, fake_codex_script())
      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server"
      )

      context = %{
        workspace_path: workspace,
        worker_host: nil,
        work_item: %{
          id: "issue-451",
          identifier: "MT-451",
          title: "Backend compatibility",
          description: "Exercise the wrapper"
        },
        on_event: fn event ->
          send(parent, {:codex_backend_event, event})
        end
      }

      assert {:ok, session} = CodexAppServer.start_session(context, [])
      assert session.backend == :codex_app_server
      assert String.ends_with?(session.workspace_path, "/workspaces/MT-451")

      turn = %{
        prompt: "Do the thing",
        work_item: context.work_item
      }

      assert {:ok, result} = CodexAppServer.run_turn(session, turn, [])
      assert result.backend == :codex_app_server
      assert result.session_id == "thread-451-turn-451"
      assert result.thread_id == "thread-451"
      assert result.turn_id == "turn-451"

      assert_receive {:codex_backend_event, session_started}
      assert session_started.backend == :codex_app_server
      assert session_started.event == :session_started
      assert session_started.session_id == "thread-451-turn-451"
      assert session_started.thread_id == "thread-451"
      assert session_started.turn_id == "turn-451"
      assert session_started.worker_pid == session_started.codex_app_server_pid

      assert_receive {:codex_backend_event, turn_completed}
      assert turn_completed.backend == :codex_app_server
      assert turn_completed.event == :turn_completed
      assert turn_completed.payload == %{"method" => "turn/completed"}
      assert turn_completed.raw == ~s({"method":"turn/completed"})

      assert :ok = CodexAppServer.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end

  defp fake_codex_script do
    """
    #!/bin/sh
    count=0

    while IFS= read -r line; do
      count=$((count + 1))

      case "$count" in
        1)
          printf '%s\n' '{"id":1,"result":{}}'
          ;;
        2)
          printf '%s\n' '{"id":2,"result":{"thread":{"id":"thread-451"}}}'
          ;;
        3)
          printf '%s\n' '{"id":3,"result":{"turn":{"id":"turn-451"}}}'
          ;;
        4)
          printf '%s\n' '{"method":"turn/completed"}'
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac
    done
    """
  end
end

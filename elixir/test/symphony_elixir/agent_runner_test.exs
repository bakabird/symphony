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

  defmodule MissingStopSessionBackend do
    def start_session(_context, _opts), do: {:ok, :missing_stop_session}

    def run_turn(_session, turn, _opts) do
      {:ok,
       %{
         backend: :missing_stop_session,
         result: :ok,
         session_id: "missing-stop-session-#{turn.turn_number}",
         thread_id: "missing-stop-thread",
         turn_id: Integer.to_string(turn.turn_number)
       }}
    end
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

  test "agent runner raises load failure when backend module cannot be loaded" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-missing-backend-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_id = "issue-missing-backend"
      issue_identifier = "MT-426"
      missing_module = Module.concat([__MODULE__, "MissingBackend#{System.unique_integer([:positive])}"])

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        title: "Missing backend",
        description: "Exercise backend module load failure",
        state: "In Progress",
        url: "https://example.org/issues/MT-426",
        labels: []
      }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root
      )

      assert_raise ArgumentError, ~r/could not be loaded/, fn ->
        AgentRunner.run(issue, self(), backend: missing_module)
      end
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner raises callback contract failure for loaded invalid backend modules" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-callback-mismatch-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      issue_id = "issue-callback-mismatch"
      issue_identifier = "MT-428"

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        title: "Callback mismatch backend",
        description: "Exercise callback contract validation",
        state: "In Progress",
        url: "https://example.org/issues/MT-428",
        labels: []
      }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root
      )

      assert_raise ArgumentError, ~r/does not implement AgentBackend callbacks: stop_session\/1/, fn ->
        AgentRunner.run(issue, self(), backend: MissingStopSessionBackend)
      end
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner uses the configured claude cli backend without an opts override" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-configured-backend-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      log_path = Path.join(test_root, "claude-runner.log")
      script_path = Path.join(test_root, "fake_claude_runner.py")
      issue_id = "issue-configured-backend"
      issue_identifier = "MT-427"

      File.mkdir_p!(test_root)
      write_fake_claude_stream_script!(script_path, log_path)
      backend_module = SymphonyElixir.AgentBackend.ClaudeCliStream
      unload_module(backend_module)

      assert :code.is_loaded(backend_module) == false

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        title: "Configured backend",
        description: "Exercise workflow-based backend selection",
        state: "In Progress",
        url: "https://example.org/issues/MT-427",
        labels: []
      }

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        max_turns: 3,
        agent_backend_id: "claude_cli_stream",
        agent_backend_command: "python3 #{script_path} #{log_path}"
      )

      Process.delete(:configured_backend_state_fetches)

      state_fetcher = fn [_issue_id] ->
        next_count = Process.get(:configured_backend_state_fetches, 0) + 1
        Process.put(:configured_backend_state_fetches, next_count)

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
                 self(),
                 issue_state_fetcher: state_fetcher,
                 max_turns: 3
               )

      assert match?({:file, _}, :code.is_loaded(backend_module))

      assert_receive {:agent_worker_update, ^issue_id, started_1}
      assert started_1.event == :session_started
      assert started_1.thread_id == "claude-session-1"
      assert started_1.session_id == "claude-session-1-turn-1"

      assert_receive {:agent_worker_update, ^issue_id, notification_1}
      assert notification_1.event == :notification
      assert notification_1.payload["type"] == "system"

      assert_receive {:agent_worker_update, ^issue_id, stream_1}
      assert stream_1.event == :notification
      assert stream_1.payload["type"] == "stream_event"

      assert_receive {:agent_worker_update, ^issue_id, completed_1}
      assert completed_1.event == :turn_completed

      assert_receive {:agent_worker_update, ^issue_id, started_2}
      assert started_2.event == :session_started
      assert started_2.thread_id == "claude-session-1"
      assert started_2.session_id == "claude-session-1-turn-2"

      assert_receive {:agent_worker_update, ^issue_id, notification_2}
      assert notification_2.event == :notification
      assert notification_2.payload["type"] == "system"

      assert_receive {:agent_worker_update, ^issue_id, stream_2}
      assert stream_2.event == :notification
      assert stream_2.payload["type"] == "stream_event"

      assert_receive {:agent_worker_update, ^issue_id, completed_2}
      assert completed_2.event == :turn_completed
      assert Process.get(:configured_backend_state_fetches) == 2

      log = File.read!(log_path)
      assert log =~ "resume=None|prompt="
      assert log =~ "resume=claude-session-1|prompt=Continuation guidance:"
    after
      Process.delete(:configured_backend_state_fetches)
      File.rm_rf(test_root)
    end
  end

  defp write_fake_claude_stream_script!(path, _log_path) do
    script =
      [
        "import json",
        "import sys",
        "",
        "args = sys.argv[2:]",
        "log_path = sys.argv[1]",
        "",
        "resume_value = None",
        "prompt = args[-1]",
        "",
        "for index, value in enumerate(args):",
        "    if value == \"--resume\":",
        "        resume_value = args[index + 1]",
        "",
        "session_id = resume_value or \"claude-session-1\"",
        "",
        "with open(log_path, \"a\", encoding=\"utf-8\") as handle:",
        "    handle.write(f\"resume={resume_value}|prompt={prompt}\\\\n\")",
        "",
        "print(json.dumps({",
        "    \"type\": \"system\",",
        "    \"subtype\": \"init\",",
        "    \"session_id\": session_id",
        "}), flush=True)",
        "",
        "print(json.dumps({",
        "    \"type\": \"stream_event\",",
        "    \"session_id\": session_id,",
        "    \"event\": {",
        "        \"type\": \"content_block_delta\",",
        "        \"delta\": {",
        "            \"type\": \"text_delta\",",
        "            \"text\": \"runner\"",
        "        }",
        "    }",
        "}), flush=True)",
        "",
        "print(json.dumps({",
        "    \"type\": \"result\",",
        "    \"subtype\": \"success\",",
        "    \"session_id\": session_id,",
        "    \"usage\": {",
        "        \"input_tokens\": 2,",
        "        \"output_tokens\": 3,",
        "        \"total_tokens\": 5",
        "    },",
        "    \"result\": prompt",
        "}), flush=True)",
        ""
      ]
      |> Enum.join("\n")

    File.write!(path, script)
  end

  defp unload_module(module) when is_atom(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end
end

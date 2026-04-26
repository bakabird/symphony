defmodule SymphonyElixir.AgentBackend.ClaudeCliStreamTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend.ClaudeCliStream

  test "claude cli stream backend resolves Claude log level from env and falls back to info" do
    with_claude_log_level("trace", fn ->
      assert {:ok, session} = ClaudeCliStream.start_session(%{}, [])
      assert Agent.get(session, &Map.fetch!(&1, :claude_log_level)) == :trace
      assert :ok = ClaudeCliStream.stop_session(session)
    end)

    with_claude_log_level("invalid-value", fn ->
      assert {:ok, session} = ClaudeCliStream.start_session(%{}, [])
      assert Agent.get(session, &Map.fetch!(&1, :claude_log_level)) == :info
      assert :ok = ClaudeCliStream.stop_session(session)
    end)

    with_claude_log_level(nil, fn ->
      assert {:ok, session} = ClaudeCliStream.start_session(%{}, [])
      assert Agent.get(session, &Map.fetch!(&1, :claude_log_level)) == :info
      assert :ok = ClaudeCliStream.stop_session(session)
    end)
  end

  test "claude cli stream backend resumes the same Claude session across turns" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-claude-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-CLAUDE")
      log_path = Path.join(test_root, "claude.log")
      script_path = Path.join(test_root, "fake_claude.py")

      File.mkdir_p!(workspace_path)
      write_fake_claude_script!(script_path, log_path)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "claude_cli_stream",
        agent_backend_command: "python3 #{script_path} #{log_path}"
      )

      parent = self()
      base_command = "python3 #{script_path} #{log_path}"
      first_expected_command = build_claude_command(base_command, "First prompt")
      second_expected_command = build_claude_command(base_command, "Second prompt", "claude-session-1")
      context = claude_test_context(parent, workspace_path)

      log =
        capture_log(fn ->
          assert {:ok, session} = ClaudeCliStream.start_session(context, [])
          assert is_pid(session)

          assert {:ok, first_result} =
                   ClaudeCliStream.run_turn(session, %{prompt: "First prompt", turn_number: 1}, [])

          assert first_result.backend == :claude_cli_stream
          assert first_result.thread_id == "claude-session-1"
          assert first_result.session_id == "claude-session-1-turn-1"
          assert first_result.turn_id == "1"
          assert first_result.result == "handled: First prompt"

          assert_receive {:claude_event, first_started}
          assert first_started.event == :session_started
          assert first_started.thread_id == "claude-session-1"
          assert first_started.session_id == "claude-session-1-turn-1"

          assert_receive {:claude_event, first_notification}
          assert first_notification.event == :notification
          assert first_notification.payload["type"] == "system"

          assert_receive {:claude_event, first_stream}
          assert first_stream.event == :notification
          assert first_stream.payload["type"] == "stream_event"

          assert_receive {:claude_event, first_completed}
          assert first_completed.event == :turn_completed
          assert first_completed.usage == %{"input_tokens" => 2, "output_tokens" => 3, "total_tokens" => 5}

          assert {:ok, second_result} =
                   ClaudeCliStream.run_turn(session, %{prompt: "Second prompt", turn_number: 2}, [])

          assert second_result.thread_id == "claude-session-1"
          assert second_result.session_id == "claude-session-1-turn-2"
          assert second_result.turn_id == "2"
          assert second_result.result == "handled: Second prompt"

          assert_receive {:claude_event, second_started}
          assert second_started.event == :session_started
          assert second_started.session_id == "claude-session-1-turn-2"

          assert_receive {:claude_event, second_notification}
          assert second_notification.event == :notification
          assert second_notification.payload["type"] == "system"

          assert_receive {:claude_event, second_stream}
          assert second_stream.event == :notification
          assert second_stream.payload["type"] == "stream_event"

          assert_receive {:claude_event, second_completed}
          assert second_completed.event == :turn_completed

          assert :ok = ClaudeCliStream.stop_session(session)
      end)

      assert log =~ first_expected_command
      assert log =~ second_expected_command

      log = File.read!(log_path)
      assert log =~ "resume=None|prompt=First prompt"
      assert log =~ "resume=claude-session-1|prompt=Second prompt"
    after
      File.rm_rf(test_root)
    end
  end

  test "claude cli stream backend gates Claude logging by level" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-claude-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-CLAUDE")
      log_path = Path.join(test_root, "claude.log")
      script_path = Path.join(test_root, "fake_claude.py")

      File.mkdir_p!(workspace_path)
      write_fake_claude_script!(script_path, log_path)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "claude_cli_stream",
        agent_backend_command: "python3 #{script_path} #{log_path}"
      )

      parent = self()
      base_command = "python3 #{script_path} #{log_path}"
      context = claude_test_context(parent, workspace_path)

      info_log =
        run_claude_turn_with_log_level(context, "info", "Info prompt")

      assert info_log =~ build_claude_command(base_command, "Info prompt")
      assert info_log =~ "Claude session started session_id=claude-session-1-turn-1"
      assert info_log =~ "Claude turn completed session_id=claude-session-1-turn-1"
      refute info_log =~ "Claude notification"

      debug_log =
        run_claude_turn_with_log_level(context, "debug", "Debug prompt")

      assert debug_log =~ build_claude_command(base_command, "Debug prompt")
      assert debug_log =~ "Claude session started session_id=claude-session-1-turn-1"
      assert debug_log =~ "Claude notification session_id=claude-session-1-turn-1"
      assert debug_log =~ "Claude turn completed session_id=claude-session-1-turn-1"

      off_log =
        run_claude_turn_with_log_level(context, "off", "Off prompt")

      refute off_log =~ "Claude"
      refute off_log =~ build_claude_command(base_command, "Off prompt")
    after
      File.rm_rf(test_root)
    end
  end

  defp write_fake_claude_script!(path, _log_path) do
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
        "            \"text\": \"working\"",
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
        "    \"result\": f\"handled: {prompt}\"",
        "}), flush=True)",
        ""
      ]
      |> Enum.join("\n")

    File.write!(path, script)
  end

  defp build_claude_command(base_command, prompt, resume_session_id \\ nil) do
    resume_arg =
      case resume_session_id do
        session_id when is_binary(session_id) and session_id != "" ->
          " --resume " <> SymphonyElixir.AgentBackend.CommandPort.shell_escape(session_id)

        _ ->
          ""
      end

    base_command <>
      " --print --output-format stream-json --verbose --include-partial-messages" <>
      resume_arg <>
      " " <> SymphonyElixir.AgentBackend.CommandPort.shell_escape(prompt)
  end

  defp run_claude_turn_with_log_level(context, level, prompt) do
    with_claude_log_level(level, fn ->
      capture_log([level: :debug], fn ->
        assert {:ok, session} = ClaudeCliStream.start_session(context, [])
        assert {:ok, result} = ClaudeCliStream.run_turn(session, %{prompt: prompt, turn_number: 1}, [])
        assert result.result == "handled: #{prompt}"
        assert :ok = ClaudeCliStream.stop_session(session)
      end)
    end)
  end

  defp with_claude_log_level(level, fun) do
    previous = System.get_env("SYMPHONY_CLAUDE_LOG_LEVEL")
    restore_env("SYMPHONY_CLAUDE_LOG_LEVEL", level)

    try do
      fun.()
    after
      restore_env("SYMPHONY_CLAUDE_LOG_LEVEL", previous)
    end
  end

  defp claude_test_context(parent, workspace_path) do
    %{
      on_event: fn event -> send(parent, {:claude_event, event}) end,
      work_item: %{
        id: "issue-claude",
        identifier: "MT-CLAUDE",
        title: "Claude backend",
        description: "Exercise Claude CLI stream"
      },
      worker_host: nil,
      workspace_path: workspace_path
    }
  end
end

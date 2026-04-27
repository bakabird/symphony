defmodule SymphonyElixir.AgentBackend.AcpStdioTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend.AcpStdio

  test "acp stdio backend runs turns, auto-approves permission requests, and closes the session" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp.log")
      script_path = Path.join(test_root, "fake_acp.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path}"
      )

      parent = self()

      context = %{
        on_event: fn event -> send(parent, {:acp_event, event}) end,
        work_item: %{
          id: "issue-acp",
          identifier: "MT-ACP",
          title: "ACP backend",
          description: "Exercise ACP stdio"
        },
        worker_host: nil,
        workspace_path: workspace_path
      }

      assert {:ok, session} = AcpStdio.start_session(context, [])
      assert session.session_id == "sess-acp-test"

      assert {:ok, result} =
               AcpStdio.run_turn(session, %{prompt: "Inspect the repository", turn_number: 1}, [])

      assert result.backend == :acp_stdio
      assert result.session_id == "sess-acp-test-turn-1"
      assert result.thread_id == "sess-acp-test"
      assert result.turn_id == "1"

      assert_receive {:acp_event, session_started}
      assert session_started.event == :session_started
      assert session_started.session_id == "sess-acp-test-turn-1"
      assert session_started.thread_id == "sess-acp-test"
      assert session_started.turn_id == "1"

      assert_receive {:acp_event, permission_request}
      assert permission_request.event == :notification
      assert permission_request.payload["method"] == "session/request_permission"

      assert_receive {:acp_event, update}
      assert update.event == :notification
      assert update.payload["method"] == "session/update"

      assert_receive {:acp_event, completed}
      assert completed.event == :turn_completed
      assert completed.session_id == "sess-acp-test-turn-1"

      assert :ok = AcpStdio.stop_session(session)

      log = File.read!(log_path)
      assert log =~ "permission=allow-once"
      assert log =~ "close=sess-acp-test"
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend tolerates noisy startup output before initialize and session creation" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-noise-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp-noise.log")
      script_path = Path.join(test_root, "fake_acp_noise.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :noise)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path} noise"
      )

      context = acp_context(workspace_path)
      assert {:ok, session} = AcpStdio.start_session(context, [])
      assert session.session_id == "sess-acp-test"
      assert :ok = AcpStdio.stop_session(session)

      log = File.read!(log_path)
      assert log =~ "session_new=ok"
      assert log =~ "close=sess-acp-test"
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend reports invalid session responses from session/new" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-invalid-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp-invalid.log")
      script_path = Path.join(test_root, "fake_acp_invalid.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :invalid_session)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path} invalid_session"
      )

      context = acp_context(workspace_path)
      assert {:error, {:invalid_session_response, %{"sessionId" => nil}}} = AcpStdio.start_session(context, [])

      log = File.read!(log_path)
      assert log =~ "session_new=invalid"
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend surfaces startup timeouts and session/new errors" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-startup-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      init_timeout_log = Path.join(test_root, "acp-init-timeout.log")
      session_error_log = Path.join(test_root, "acp-session-error.log")
      init_timeout_script = Path.join(test_root, "fake_acp_init_timeout.py")
      session_error_script = Path.join(test_root, "fake_acp_session_error.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(init_timeout_script, init_timeout_log, :init_timeout)
      write_fake_acp_script!(session_error_script, session_error_log, :session_new_error)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{init_timeout_script} #{init_timeout_log} init_timeout",
        agent_backend_read_timeout_ms: 50
      )

      assert {:error, :read_timeout} = AcpStdio.start_session(acp_context(workspace_path), [])

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{session_error_script} #{session_error_log} session_new_error"
      )

      assert {:error, {:json_rpc_error, %{"message" => "session new failed"}}} =
               AcpStdio.start_session(acp_context(workspace_path), [])
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend covers response and capability fallbacks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-response-fallbacks-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      init_exit_log = Path.join(test_root, "acp-init-exit.log")
      capability_log = Path.join(test_root, "acp-capability.log")
      permission_nil_log = Path.join(test_root, "acp-permission-nil.log")
      init_exit_script = Path.join(test_root, "fake_acp_init_exit.py")
      capability_script = Path.join(test_root, "fake_acp_capability.py")
      permission_nil_script = Path.join(test_root, "fake_acp_permission_nil.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(init_exit_script, init_exit_log, :init_exit)
      write_fake_acp_script!(capability_script, capability_log, :init_no_caps)
      write_fake_acp_script!(permission_nil_script, permission_nil_log, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{init_exit_script} #{init_exit_log} init_exit",
        agent_backend_read_timeout_ms: 1_000
      )

      assert {:error, {:port_exit, 0}} = AcpStdio.start_session(acp_context(workspace_path), [])

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{capability_script} #{capability_log} init_no_caps"
      )

      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      assert session.session_capabilities == %{}

      unsupported_session = %{session | session_capabilities: :not_a_map}
      assert :ok = AcpStdio.stop_session(unsupported_session)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{permission_nil_script} #{permission_nil_log} success"
      )

      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      assert {:ok, _} = AcpStdio.run_turn(session, %{prompt: "permission-nil-params", turn_number: 1}, [])
      assert :ok = AcpStdio.stop_session(session)

      capability_log_contents = File.read!(capability_log)
      permission_nil_log_contents = File.read!(permission_nil_log)

      refute File.exists?(init_exit_log)
      assert capability_log_contents =~ "session_new=ok"
      assert permission_nil_log_contents =~ "permission=None"
      assert permission_nil_log_contents =~ "close=sess-acp-test"
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend covers startup and prompt fallback branches" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-fallbacks-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      init_no_caps_log = Path.join(test_root, "acp-init-no-caps.log")
      init_nonmap_log = Path.join(test_root, "acp-init-nonmap.log")
      session_exit_log = Path.join(test_root, "acp-session-exit.log")
      prompt_log = Path.join(test_root, "acp-prompt-fallbacks.log")
      init_no_caps_script = Path.join(test_root, "fake_acp_init_no_caps.py")
      init_nonmap_script = Path.join(test_root, "fake_acp_init_nonmap.py")
      session_exit_script = Path.join(test_root, "fake_acp_session_exit.py")
      prompt_script = Path.join(test_root, "fake_acp_prompt_fallbacks.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(init_no_caps_script, init_no_caps_log, :init_no_caps)
      write_fake_acp_script!(init_nonmap_script, init_nonmap_log, :init_nonmap)
      write_fake_acp_script!(session_exit_script, session_exit_log, :session_new_exit)
      write_fake_acp_script!(prompt_script, prompt_log, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{init_no_caps_script} #{init_no_caps_log} init_no_caps"
      )

      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      assert session.session_capabilities == %{}
      assert :ok = AcpStdio.stop_session(session)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{init_nonmap_script} #{init_nonmap_log} init_nonmap"
      )

      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      assert session.session_capabilities == %{}
      assert :ok = AcpStdio.stop_session(session)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{session_exit_script} #{session_exit_log} session_new_exit"
      )

      assert {:error, {:port_exit, 0}} = AcpStdio.start_session(acp_context(workspace_path), [])

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{prompt_script} #{prompt_log} success"
      )

      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      assert {:ok, _} = AcpStdio.run_turn(session, %{prompt: "generic notification", turn_number: 1}, [])
      assert {:ok, _} = AcpStdio.run_turn(session, %{prompt: "permission-no-options", turn_number: 2}, [])
      assert {:ok, _} = AcpStdio.run_turn(session, %{prompt: "permission-empty-options", turn_number: 3}, [])
      assert :ok = AcpStdio.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend surfaces turn failures, timeouts, and JSON-RPC errors" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-turns-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp-turns.log")
      script_path = Path.join(test_root, "fake_acp_turns.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path} success",
        agent_backend_turn_timeout_ms: 50
      )

      context = acp_context(workspace_path)
      assert {:ok, session} = AcpStdio.start_session(context, [])

      assert {:ok, result} = AcpStdio.run_turn(session, %{prompt: "fail turn", turn_number: 1}, [])
      assert result.result["subtype"] == "error"

      assert {:error, {:json_rpc_error, %{"message" => "prompt failed"}}} =
               AcpStdio.run_turn(session, %{prompt: "json-rpc-error turn", turn_number: 2}, [])

      assert {:error, :turn_timeout} =
               AcpStdio.run_turn(session, %{prompt: "timeout turn", turn_number: 3}, [])

      assert :ok = AcpStdio.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend handles malformed and unknown prompt responses" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-prompt-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp-prompt.log")
      script_path = Path.join(test_root, "fake_acp_prompt.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path} success"
      )

      context = acp_context(workspace_path)
      assert {:ok, session} = AcpStdio.start_session(context, [])

      assert {:ok, _result} =
               AcpStdio.run_turn(session, %{prompt: "malformed prompt", turn_number: 1}, [])

      assert {:ok, _result} =
               AcpStdio.run_turn(session, %{prompt: "method-not-found prompt", turn_number: 2}, [])

      assert :ok = AcpStdio.stop_session(session)
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend surfaces prompt port exits and stop fallback" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-acp-exit-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace_path = Path.join(workspace_root, "MT-ACP")
      log_path = Path.join(test_root, "acp-exit.log")
      script_path = Path.join(test_root, "fake_acp_exit.py")

      File.mkdir_p!(workspace_path)
      write_fake_acp_script!(script_path, log_path, :success)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_backend_id: "acp_stdio",
        agent_backend_command: "python3 #{script_path} #{log_path} success"
      )

      context = acp_context(workspace_path)
      assert {:ok, session} = AcpStdio.start_session(context, [])
      assert {:error, {:port_exit, 0}} = AcpStdio.run_turn(session, %{prompt: "exit prompt", turn_number: 1}, [])
      assert :ok = AcpStdio.stop_session(%{})
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend stops sessions without issuing session/close when unsupported" do
    {test_root, workspace_root, workspace_path, log_path, script_path} = prepare_acp_workspace!("acp-no-close")
    write_fake_acp_script!(script_path, log_path, :success)

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: workspace_root,
      agent_backend_id: "acp_stdio",
      agent_backend_command: "python3 #{script_path} #{log_path} success"
    )

    try do
      assert {:ok, session} = AcpStdio.start_session(acp_context(workspace_path), [])
      port_session = %{session | session_capabilities: %{}}
      assert :ok = AcpStdio.stop_session(port_session)

      log = File.read!(log_path)
      assert log =~ "session_new=ok"
      refute log =~ "close=sess-acp-test"
    after
      File.rm_rf(test_root)
    end
  end

  test "acp stdio backend stop_session/1 accepts non-port values" do
    assert :ok = AcpStdio.stop_session(:not_a_session)
  end

  defp acp_context(workspace_path) do
    parent = self()

    %{
      on_event: fn event -> send(parent, {:acp_event, event}) end,
      work_item: %{
        id: "issue-acp",
        identifier: "MT-ACP",
        title: "ACP backend",
        description: "Exercise ACP stdio"
      },
      worker_host: nil,
      workspace_path: workspace_path
    }
  end

  defp prepare_acp_workspace!(label) do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-backend-#{label}-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    workspace_path = Path.join(workspace_root, "MT-ACP")
    log_path = Path.join(test_root, "#{label}.log")
    script_path = Path.join(test_root, "#{label}.py")

    File.mkdir_p!(workspace_path)

    {test_root, workspace_root, workspace_path, log_path, script_path}
  end

  defp write_fake_acp_script!(path, _log_path, _mode) do
    script =
      [
        "import json",
        "import sys",
        "import time",
        "",
        "log_path = sys.argv[1]",
        "mode = sys.argv[2] if len(sys.argv) > 2 else \"success\"",
        "session_id = \"sess-acp-test\"",
        "",
        "def log(message):",
        "    with open(log_path, \"a\", encoding=\"utf-8\") as handle:",
        "        handle.write(message + \"\\\\n\")",
        "",
        "def emit_startup_noise():",
        "    if mode != \"noise\":",
        "        return",
        "",
        "    print(\"not-json\", flush=True)",
        "    print(json.dumps({",
        "        \"jsonrpc\": \"2.0\",",
        "        \"id\": 99,",
        "        \"method\": \"session/update\",",
        "        \"params\": {",
        "            \"sessionId\": session_id,",
        "            \"update\": {",
        "                \"sessionUpdate\": \"agent_message_chunk\",",
        "                \"content\": {",
        "                    \"type\": \"text\",",
        "                    \"text\": \"noise\"",
        "                }",
        "            }",
        "        }",
        "    }), flush=True)",
        "",
        "for line in sys.stdin:",
        "    line = line.strip()",
        "    if not line:",
        "        continue",
        "",
        "    payload = json.loads(line)",
        "    method = payload.get(\"method\")",
        "",
        "    if method == \"initialize\":",
        "        emit_startup_noise()",
        "",
        "        if mode == \"init_timeout\":",
        "            time.sleep(1)",
        "            continue",
        "",
        "        if mode == \"init_exit\":",
        "            break",
        "",
        "        if mode == \"init_no_caps\":",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"protocolVersion\": 1",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if mode == \"init_nonmap\":",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": []",
        "            }), flush=True)",
        "            continue",
        "",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": payload[\"id\"],",
        "            \"result\": {",
        "                \"protocolVersion\": 1,",
        "                \"agentCapabilities\": {",
        "                    \"sessionCapabilities\": {",
        "                        \"close\": {}",
        "                    }",
        "                }",
        "            }",
        "        }), flush=True)",
        "",
        "    elif method == \"session/new\":",
        "        if mode == \"session_new_timeout\":",
        "            time.sleep(1)",
        "            continue",
        "",
        "        if mode == \"session_new_exit\":",
        "            break",
        "",
        "        if mode == \"session_new_error\":",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"error\": {",
        "                    \"message\": \"session new failed\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if mode == \"invalid_session\":",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"sessionId\": None",
        "                }",
        "            }), flush=True)",
        "            log(\"session_new=invalid\")",
        "            continue",
        "",
        "        log(\"session_new=ok\")",
        "",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": payload[\"id\"],",
        "            \"result\": {",
        "                \"sessionId\": session_id",
        "            }",
        "        }), flush=True)",
        "    elif method == \"session/prompt\":",
        "        prompt_text = payload[\"params\"][\"prompt\"][0][\"text\"]",
        "",
        "        if \"timeout\" in prompt_text:",
        "            time.sleep(1)",
        "            continue",
        "",
        "        if \"json-rpc-error\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"error\": {",
        "                    \"message\": \"prompt failed\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"fail\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"subtype\": \"error\",",
        "                    \"result\": \"failed\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"exit\" in prompt_text:",
        "            break",
        "",
        "        if \"method-not-found\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": 91,",
        "                \"method\": \"session/unknown\",",
        "                \"params\": {",
        "                    \"sessionId\": session_id",
        "                }",
        "            }), flush=True)",
        "",
        "            _ = json.loads(sys.stdin.readline())",
        "",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"stopReason\": \"end_turn\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"permission-no-options\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": 90,",
        "                \"method\": \"session/request_permission\",",
        "                \"params\": {",
        "                    \"sessionId\": session_id,",
        "                    \"toolCall\": {",
        "                        \"toolCallId\": \"call-1\"",
        "                    }",
        "                }",
        "            }), flush=True)",
        "",
        "            permission_response = json.loads(sys.stdin.readline())",
        "            option_id = permission_response[\"result\"][\"outcome\"][\"optionId\"]",
        "            log(f\"permission={option_id}\")",
        "",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"stopReason\": \"end_turn\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"permission-empty-options\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": 90,",
        "                \"method\": \"session/request_permission\",",
        "                \"params\": {",
        "                    \"sessionId\": session_id,",
        "                    \"toolCall\": {",
        "                        \"toolCallId\": \"call-1\"",
        "                    },",
        "                    \"options\": []",
        "                }",
        "            }), flush=True)",
        "",
        "            permission_response = json.loads(sys.stdin.readline())",
        "            option_id = permission_response[\"result\"][\"outcome\"][\"optionId\"]",
        "            log(f\"permission={option_id}\")",
        "",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"stopReason\": \"end_turn\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"permission-nil-params\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": 90,",
        "                \"method\": \"session/request_permission\",",
        "                \"params\": None",
        "            }), flush=True)",
        "",
        "            permission_response = json.loads(sys.stdin.readline())",
        "            option_id = permission_response[\"result\"][\"outcome\"][\"optionId\"]",
        "            log(f\"permission={option_id}\")",
        "",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"id\": payload[\"id\"],",
        "                \"result\": {",
        "                    \"stopReason\": \"end_turn\"",
        "                }",
        "            }), flush=True)",
        "            continue",
        "",
        "        if \"generic notification\" in prompt_text:",
        "            print(json.dumps({",
        "                \"jsonrpc\": \"2.0\",",
        "                \"params\": {",
        "                    \"notice\": \"hello\"",
        "                }",
        "            }), flush=True)",
        "",
        "        if \"malformed\" in prompt_text:",
        "            print(\"not-json\", flush=True)",
        "",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": 90,",
        "            \"method\": \"session/request_permission\",",
        "            \"params\": {",
        "                \"sessionId\": session_id,",
        "                \"toolCall\": {",
        "                    \"toolCallId\": \"call-1\"",
        "                },",
        "                \"options\": [",
        "                    {",
        "                        \"optionId\": \"allow-once\",",
        "                        \"name\": \"Allow once\",",
        "                        \"kind\": \"allow_once\"",
        "                    },",
        "                    {",
        "                        \"optionId\": \"reject-once\",",
        "                        \"name\": \"Reject\",",
        "                        \"kind\": \"reject_once\"",
        "                    }",
        "                ]",
        "            }",
        "        }), flush=True)",
        "",
        "        permission_response = json.loads(sys.stdin.readline())",
        "        option_id = permission_response[\"result\"][\"outcome\"][\"optionId\"]",
        "        log(f\"permission={option_id}\")",
        "",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"method\": \"session/update\",",
        "            \"params\": {",
        "                \"sessionId\": session_id,",
        "                \"update\": {",
        "                    \"sessionUpdate\": \"agent_message_chunk\",",
        "                    \"content\": {",
        "                        \"type\": \"text\",",
        "                        \"text\": \"working\"",
        "                    }",
        "                }",
        "            }",
        "        }), flush=True)",
        "",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": payload[\"id\"],",
        "            \"result\": {",
        "                \"stopReason\": \"end_turn\"",
        "            }",
        "        }), flush=True)",
        "    elif method == \"session/close\":",
        "        log(f\"close={payload['params']['sessionId']}\")",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": payload[\"id\"],",
        "            \"result\": {}",
        "        }), flush=True)",
        "        break",
        ""
      ]
      |> Enum.join("\n")

    File.write!(path, script)
    File.chmod!(path, 0o755)
  end
end

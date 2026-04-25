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
      write_fake_acp_script!(script_path, log_path)

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

  defp write_fake_acp_script!(path, _log_path) do
    script =
      [
        "import json",
        "import sys",
        "",
        "log_path = sys.argv[1]",
        "session_id = \"sess-acp-test\"",
        "",
        "def log(message):",
        "    with open(log_path, \"a\", encoding=\"utf-8\") as handle:",
        "        handle.write(message + \"\\\\n\")",
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
        "    elif method == \"session/new\":",
        "        print(json.dumps({",
        "            \"jsonrpc\": \"2.0\",",
        "            \"id\": payload[\"id\"],",
        "            \"result\": {",
        "                \"sessionId\": session_id",
        "            }",
        "        }), flush=True)",
        "    elif method == \"session/prompt\":",
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
  end
end

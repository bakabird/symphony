defmodule SymphonyElixir.AgentBackend.CommandPortTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend.CommandPort

  test "start/4, send_json/2, receive_json/3, and stop/1 handle a local command port" do
    {test_root, workspace_root, workspace_path} = prepare_workspace!()
    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

    try do
      assert {:ok, session} = CommandPort.start(workspace_path, nil, "cat", line_bytes: 256)
      assert String.ends_with?(session.workspace, "/workspaces/MT-COMMAND")
      assert session.worker_host == nil
      assert is_binary(session.metadata.worker_pid)
      assert session.metadata.codex_app_server_pid == session.metadata.worker_pid

      assert :ok = CommandPort.send_json(session.port, %{"hello" => "world"})
      assert {:ok, %{"hello" => "world"}, ""} = CommandPort.receive_json(session.port, 1_000)
      assert :ok = CommandPort.stop(session)

      assert {:ok, exit_session} = CommandPort.start(workspace_path, nil, "exit 0", line_bytes: 256)
      Process.sleep(50)
      assert :ok = CommandPort.stop(exit_session)

      assert :ok = CommandPort.stop(%{})
    after
      File.rm_rf(test_root)
    end
  end

  test "receive_json/3 handles malformed payloads, partial lines, exit status, and timeouts" do
    {test_root, workspace_root, workspace_path} = prepare_workspace!()
    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

    try do
      assert {:ok, map_port} = CommandPort.start(workspace_path, nil, "printf '{\"hello\":\"world\"}\\n'; sleep 1", line_bytes: 256)
      assert {:ok, %{"hello" => "world"}, ""} = CommandPort.receive_json(map_port.port, 1_000)
      assert :ok = CommandPort.stop(map_port)

      assert {:ok, list_port} = CommandPort.start(workspace_path, nil, "printf '[]\\n'; sleep 1", line_bytes: 256)
      assert {:malformed, "[]", ""} = CommandPort.receive_json(list_port.port, 1_000)
      assert :ok = CommandPort.stop(list_port)

      assert {:ok, invalid_port} = CommandPort.start(workspace_path, nil, "printf '{not-json}\\n'; sleep 1", line_bytes: 256)
      assert {:malformed, "{not-json}", ""} = CommandPort.receive_json(invalid_port.port, 1_000)
      assert :ok = CommandPort.stop(invalid_port)

      assert {:ok, partial_port} =
               CommandPort.start(
                 workspace_path,
                 nil,
                 "python3 -c 'import sys; sys.stdout.write(\"{\\\"partial\\\":\\\"\" + (\"x\" * 512) + \"\\\"}\"); sys.stdout.flush()'",
                 line_bytes: 32
               )

      assert {:error, _reason} = CommandPort.receive_json(partial_port.port, 1_000)
      assert :ok = CommandPort.stop(partial_port)

      assert {:ok, exit_port} = CommandPort.start(workspace_path, nil, "exit 7", line_bytes: 256)
      assert {:error, {:port_exit, 7}} = CommandPort.receive_json(exit_port.port, 1_000)
      assert :ok = CommandPort.stop(exit_port)

      assert {:ok, sleeper} = CommandPort.start(workspace_path, nil, "sleep 1", line_bytes: 256)
      assert :ok = CommandPort.stop(sleeper)

      assert {:ok, queued_exit_port} = CommandPort.start(workspace_path, nil, "cat", line_bytes: 256)
      send(self(), {queued_exit_port.port, {:exit_status, 0}})
      assert :ok = CommandPort.stop(queued_exit_port)
    after
      File.rm_rf(test_root)
    end
  end

  test "start/4 validates local and remote workspace inputs" do
    {test_root, workspace_root, workspace_path} = prepare_workspace!()
    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

    outside_workspace = Path.join(test_root, "outside")
    unreadable_parent = Path.join(test_root, "unreadable")
    unreadable_workspace = Path.join(unreadable_parent, "missing")
    symlink_workspace = Path.join(workspace_root, "symlink_escape")
    File.mkdir_p!(outside_workspace)
    File.mkdir_p!(unreadable_parent)
    File.ln_s!(outside_workspace, symlink_workspace)
    File.chmod!(unreadable_parent, 0o000)

    try do
      assert {:error, {:invalid_workspace_cwd, :workspace_root, _}} = CommandPort.start(workspace_root, nil, "cat")
      assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, _, _}} = CommandPort.start(outside_workspace, nil, "cat")
      assert {:error, {:invalid_workspace_cwd, :symlink_escape, _, _}} = CommandPort.start(symlink_workspace, nil, "cat")
      assert {:error, {:invalid_workspace_cwd, :path_unreadable, _, _}} = CommandPort.start(unreadable_workspace, nil, "cat")
      assert {:error, {:invalid_workspace_cwd, :empty_remote_workspace, "worker-1"}} = CommandPort.start("", "worker-1", "cat")
      assert {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, "worker-1", "bad\npath"}} = CommandPort.start("bad\npath", "worker-1", "cat")
      assert {:error, :bash_not_found} = with_modified_path(fn -> CommandPort.start(workspace_path, nil, "cat") end)

      assert {:error, :ssh_not_found} =
               with_modified_path(fn ->
                 CommandPort.start(workspace_path, "worker-1", "cat")
               end)
    after
      File.chmod!(unreadable_parent, 0o755)
      File.rm_rf(test_root)
    end
  end

  test "start/4 supports a remote worker when ssh is available" do
    {test_root, workspace_root, workspace_path} = prepare_workspace!()
    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

    fake_bin = Path.join(test_root, "bin")
    File.mkdir_p!(fake_bin)
    write_fake_ssh_script!(Path.join(fake_bin, "ssh"))

    original_path = System.get_env("PATH")
    System.put_env("PATH", fake_bin <> ":" <> (original_path || ""))

    try do
      assert {:ok, session} = CommandPort.start(workspace_path, "worker.example", "printf '{\"remote\":true}\\n'", line_bytes: 256)
      assert session.worker_host == "worker.example"
      assert session.metadata.worker_host == "worker.example"
      assert is_binary(session.metadata.worker_pid)
      assert :ok = CommandPort.stop(session)
    after
      restore_env("PATH", original_path)
      File.rm_rf(test_root)
    end
  end

  test "shell_escape/1 escapes embedded single quotes" do
    assert CommandPort.shell_escape("a'b") == "'a'\"'\"'b'"
  end

  defp prepare_workspace! do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-command-port-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspaces")
    workspace_path = Path.join(workspace_root, "MT-COMMAND")
    File.mkdir_p!(workspace_path)

    {test_root, workspace_root, workspace_path}
  end

  defp with_modified_path(fun) when is_function(fun, 0) do
    original_path = System.get_env("PATH")
    fake_path = Path.join(System.tmp_dir!(), "symphony-elixir-empty-path-#{System.unique_integer([:positive])}")
    File.mkdir_p!(fake_path)
    System.put_env("PATH", fake_path)

    try do
      fun.()
    after
      restore_env("PATH", original_path)
      File.rm_rf(fake_path)
    end
  end

  defp write_fake_ssh_script!(path) do
    script =
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "remote_command=\"${!#}\"",
        "exec bash -lc \"$remote_command\""
      ]
      |> Enum.join("\n")

    File.write!(path, script)
    File.chmod!(path, 0o755)
  end
end

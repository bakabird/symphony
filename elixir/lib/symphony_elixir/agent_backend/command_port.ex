defmodule SymphonyElixir.AgentBackend.CommandPort do
  @moduledoc false

  alias SymphonyElixir.{Config, Json, PathSafety, SSH}

  @default_line_bytes 1_048_576

  @type t :: %{
          port: port(),
          workspace: String.t(),
          worker_host: String.t() | nil,
          metadata: map()
        }

  @spec start(String.t(), String.t() | nil, String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(workspace, worker_host, command, opts \\ [])
      when is_binary(workspace) and is_binary(command) do
    line_bytes = Keyword.get(opts, :line_bytes, @default_line_bytes)

    with {:ok, expanded_workspace} <- validate_workspace_cwd(workspace, worker_host),
         {:ok, port} <- start_port(expanded_workspace, worker_host, command, line_bytes) do
      {:ok,
       %{
         port: port,
         workspace: expanded_workspace,
         worker_host: worker_host,
         metadata: port_metadata(port, worker_host)
       }}
    end
  end

  @spec stop(t() | map()) :: :ok
  def stop(%{port: port}) when is_port(port) do
    Port.close(port)

    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      100 -> :ok
    end
  catch
    :error, _reason -> :ok
  end

  def stop(_session), do: :ok

  @spec send_json(port(), map()) :: :ok
  def send_json(port, message) when is_port(port) and is_map(message) do
    Port.command(port, Json.encode!(message) <> "\n")
    :ok
  end

  @spec receive_json(port(), timeout(), String.t()) ::
          {:ok, map(), String.t()} | {:malformed, String.t(), String.t()} | {:error, term()}
  def receive_json(port, timeout_ms, pending_line \\ "")
      when is_port(port) and is_integer(timeout_ms) and timeout_ms >= 0 and is_binary(pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)

        case Jason.decode(complete_line) do
          {:ok, payload} when is_map(payload) ->
            {:ok, payload, ""}

          {:ok, payload} ->
            {:malformed, inspect(payload), ""}

          {:error, _reason} ->
            {:malformed, complete_line, ""}
        end

      {^port, {:data, {:noeol, chunk}}} ->
        receive_json(port, timeout_ms, pending_line <> to_string(chunk))

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        {:error, :timeout}
    end
  end

  @spec shell_escape(String.t()) :: String.t()
  def shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp validate_workspace_cwd(workspace, nil) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(Config.settings!().workspace.root)
    expanded_root_prefix = expanded_root <> "/"

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      canonical_root_prefix = canonical_root <> "/"

      cond do
        canonical_workspace == canonical_root ->
          {:error, {:invalid_workspace_cwd, :workspace_root, canonical_workspace}}

        String.starts_with?(canonical_workspace <> "/", canonical_root_prefix) ->
          {:ok, canonical_workspace}

        String.starts_with?(expanded_workspace <> "/", expanded_root_prefix) ->
          {:error, {:invalid_workspace_cwd, :symlink_escape, expanded_workspace, canonical_root}}

        true ->
          {:error, {:invalid_workspace_cwd, :outside_workspace_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  defp validate_workspace_cwd(workspace, worker_host)
       when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}

      true ->
        {:ok, workspace}
    end
  end

  defp start_port(workspace, nil, command, line_bytes) do
    case System.find_executable("bash") do
      nil ->
        {:error, :bash_not_found}

      executable ->
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(executable)},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: [~c"-lc", String.to_charlist(command)],
              cd: String.to_charlist(workspace),
              line: line_bytes
            ]
          )

        {:ok, port}
    end
  end

  defp start_port(workspace, worker_host, command, line_bytes) when is_binary(worker_host) do
    remote_command =
      [
        "cd #{shell_escape(workspace)}",
        "exec #{command}"
      ]
      |> Enum.join(" && ")

    SSH.start_port(worker_host, remote_command, line: line_bytes)
  end

  defp port_metadata(port, worker_host) when is_port(port) do
    base_metadata =
      case :erlang.port_info(port, :os_pid) do
        {:os_pid, os_pid} ->
          pid = to_string(os_pid)
          %{worker_pid: pid, codex_app_server_pid: pid}

        _ ->
          %{}
      end

    case worker_host do
      host when is_binary(host) -> Map.put(base_metadata, :worker_host, host)
      _ -> base_metadata
    end
  end
end

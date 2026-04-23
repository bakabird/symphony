defmodule SymphonyElixir.AgentBackendTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend
  alias SymphonyElixir.AgentBackend.CodexAppServer
  alias SymphonyElixir.AgentBackend.Resolver

  test "normalize_runtime_event handles string keys and passthrough values" do
    timestamp = DateTime.utc_now()

    event =
      AgentBackend.normalize_runtime_event(nil, %{
        "event" => "notification",
        "timestamp" => timestamp,
        "session_id" => "thread-2-turn-2",
        "thread_id" => "thread-2",
        "turn_id" => "turn-2",
        "codex_app_server_pid" => "4321",
        "payload" => %{"method" => "turn/completed"},
        "raw" => "raw"
      })

    assert event.backend == :unknown_backend
    assert event.event == "notification"
    assert event.timestamp == timestamp
    assert event.session_id == "thread-2-turn-2"
    assert event.thread_id == "thread-2"
    assert event.turn_id == "turn-2"
    assert event.worker_pid == "4321"
    assert event.codex_app_server_pid == "4321"
    assert event.payload == %{"method" => "turn/completed"}
    assert event.raw == "raw"
    assert AgentBackend.normalize_runtime_event(:codex_app_server, :ok) == :ok
    assert AgentBackend.normalize_backend_name(:fake_backend) == :fake_backend
    assert AgentBackend.normalize_backend_name("codex") == "codex"

    assert AgentBackend.normalize_backend_name({:tuple, :backend}) ==
             {:tuple, :backend}

    assert AgentBackend.normalize_work_item(%{
             "id" => "issue-1",
             :identifier => "MT-1",
             "title" => "Backend task",
             "description" => "Fill in shared fields"
           }) == %{
             id: "issue-1",
             identifier: "MT-1",
             title: "Backend task",
             description: "Fill in shared fields"
           }

    assert AgentBackend.value_from(%{"worker_pid" => "4242"}, :worker_pid) == "4242"
  end

  test "normalize_runtime_event fills defaults for sparse payloads" do
    event =
      AgentBackend.normalize_runtime_event(:demo_backend, %{
        "event" => "notification",
        "worker_pid" => "999"
      })

    assert event.backend == :demo_backend
    assert event.event == "notification"
    assert event.worker_pid == "999"
    assert %DateTime{} = event.timestamp
    assert AgentBackend.normalize_runtime_event(:demo_backend, "raw") == "raw"
  end

  test "resolver defaults to codex app server and honors overrides" do
    assert Resolver.resolve() == CodexAppServer
    assert Resolver.resolve(backend: :fake_backend) == :fake_backend
    assert Resolver.resolve(backend_module: Resolver) == Resolver

    assert Resolver.resolve(backend: :fake_backend, backend_module: Resolver) ==
             :fake_backend
  end
end

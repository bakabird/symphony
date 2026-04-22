## 1. Backend Contract

- [x] 1.1 Add `SymphonyElixir.AgentBackend` behaviour with callbacks for `start_session/2`, `run_turn/3`, and `stop_session/1`.
- [x] 1.2 Define lightweight backend context, turn, session, result, and event type documentation in the backend module.
- [x] 1.3 Add a backend resolver module that defaults to `codex_app_server` and supports a test override through AgentRunner options.
- [x] 1.4 Add helper logic for normalizing backend runtime events with `:backend`, `:event`, `:timestamp`, optional IDs, telemetry, raw payloads, and preserved backend-specific fields.

## 2. Codex Compatibility Backend

- [x] 2.1 Add `SymphonyElixir.AgentBackend.CodexAppServer` as the default backend implementation.
- [x] 2.2 Delegate Codex session startup, turn execution, and session stop to `SymphonyElixir.Codex.AppServer`.
- [x] 2.3 Adapt backend context and turn data into the existing Codex app-server call shape without changing Codex protocol behavior.
- [x] 2.4 Map Codex app-server callback messages into normalized backend events while preserving existing fields such as `:codex_app_server_pid`, `:usage`, `:payload`, and `:raw`.
- [x] 2.5 Keep `Codex.AppServer` public APIs and protocol tests intact.

## 3. AgentRunner Integration

- [x] 3.1 Replace direct `SymphonyElixir.Codex.AppServer` calls in `AgentRunner` with resolved backend calls.
- [x] 3.2 Build backend context from the current workspace, worker host, work item identifiers, and title before starting the session.
- [x] 3.3 Build backend turn maps from the rendered first-turn prompt and continuation prompts.
- [x] 3.4 Ensure backend sessions are stopped in the existing `after` cleanup path for success and failure.
- [x] 3.5 Update continuation guidance wording to refer to the previous agent turn instead of the previous Codex turn.
- [x] 3.6 Forward backend runtime events using an agent-neutral worker update message for the orchestrator.

## 4. Orchestrator and Observability Compatibility

- [x] 4.1 Add orchestrator handling for agent-neutral worker update messages.
- [x] 4.2 Preserve handling for legacy `:codex_worker_update` messages during migration.
- [x] 4.3 Reuse the existing token usage and rate-limit extraction for normalized backend events.
- [x] 4.4 Preserve existing `codex_*` running-entry, snapshot, dashboard, and presenter fields for compatibility.
- [x] 4.5 Adjust stall detection wording and activity handling so it is based on backend agent activity while still using existing timestamp fields where retained.

## 5. Specification and Documentation Updates

- [x] 5.1 Update `SPEC.md` to define the AgentBackend runtime contract and default `codex_app_server` compatibility path.
- [x] 5.2 Keep the Codex app-server protocol details in `SPEC.md` as the Codex backend subsection rather than the whole agent runner contract.
- [x] 5.3 Document that ACP/OpenCode and Claude CLI stream backends are deferred future implementations.
- [x] 5.4 Avoid changing existing `WORKFLOW.md` `codex` configuration requirements in this change.

## 6. Tests

- [x] 6.1 Add AgentRunner tests with a fake backend proving `start_session`, `run_turn`, event forwarding, continuation, and `stop_session` behavior.
- [x] 6.2 Add Codex compatibility backend tests proving the wrapper delegates to the existing app-server behavior and normalizes callback events.
- [x] 6.3 Add orchestrator tests proving agent-neutral updates refresh activity, session identity, token totals, and rate-limit state.
- [x] 6.4 Add orchestrator tests proving legacy `:codex_worker_update` messages remain accepted.
- [x] 6.5 Keep existing Codex app-server tests passing without weakening protocol assertions.
- [x] 6.6 Update dashboard or presenter snapshot tests only where needed to account for normalized events while preserving existing output fields.

## 7. Verification

- [x] 7.1 Run `mise exec -- mix test test/symphony_elixir/app_server_test.exs`.
- [x] 7.2 Run `mise exec -- mix test test/symphony_elixir/core_test.exs`.
- [x] 7.3 Run `mise exec -- mix test test/symphony_elixir/orchestrator_status_test.exs`.
- [x] 7.4 Run `mise exec -- mix test test/symphony_elixir/status_dashboard_snapshot_test.exs`.
- [x] 7.5 Run `mise exec -- mix test test/symphony_elixir/workspace_and_config_test.exs`.
- [x] 7.6 Run `mise exec -- mix specs.check`.
- [x] 7.7 If `mise` blocks on untrusted local config, report that explicitly and do not run `mise trust` unless the operator approves.

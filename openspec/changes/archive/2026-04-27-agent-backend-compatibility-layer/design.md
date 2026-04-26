## Context

Symphony currently has a useful runtime split between polling/orchestration, workspace creation, prompt building, and Codex app-server execution, but the execution boundary is not backend-neutral yet. `AgentRunner` directly calls `SymphonyElixir.Codex.AppServer`, while the orchestrator treats `codex_*` activity as the source of truth for session identity, token accounting, rate limits, stall detection, and dashboard snapshots.

The next backend families have different shapes:

- Codex app-server is a long-lived JSON-RPC-like stdio process with `thread/start` and repeated `turn/start`.
- ACP-backed agents such as OpenCode can be modeled as long-lived stdio protocol sessions, but with ACP method names and event shapes.
- Claude Code CLI stream integration is likely a logical session over one or more command invocations using stream/json output and resume/session options.

Because of that, the shared abstraction must be a logical agent backend contract, not a Codex protocol wrapper and not an ACP-only abstraction.

## Goals / Non-Goals

**Goals:**

- Introduce a small `AgentBackend` behaviour for logical agent sessions and turns.
- Route `AgentRunner` through a backend resolver instead of directly depending on `Codex.AppServer`.
- Add a `codex_app_server` backend wrapper that preserves current Codex behavior.
- Normalize backend runtime events enough for the orchestrator to consume agent activity independent of a concrete backend.
- Preserve existing `codex` workflow configuration as the default compatibility path.
- Leave current `Codex.AppServer` protocol tests meaningful and avoid broad dashboard/API churn in the first change.

**Non-Goals:**

- Do not implement `acp_stdio`, `opencode acp`, `claude_cli_stream`, or `opencode_http`.
- Do not replace the `codex` workflow block with a generalized `agent_backend` configuration block.
- Do not rename every persisted or presented `codex_*` metric field.
- Do not redesign Work Channel, `WorkItem`, `ProgressNote`, or `linear_graphql`.
- Do not change the agent-facing workflow instructions beyond any wording needed to remove unnecessary Codex-only continuation language.

## Decisions

### Decision 1: Add `AgentBackend` as the boundary above protocol adapters

Introduce `SymphonyElixir.AgentBackend` with callbacks shaped around logical sessions:

```elixir
@callback start_session(context(), keyword()) :: {:ok, session()} | {:error, term()}
@callback run_turn(session(), turn(), keyword()) :: {:ok, turn_result()} | {:error, term()}
@callback stop_session(session()) :: :ok
```

The context should contain backend-independent values such as workspace path, worker host, work item title, work item identifiers, and `on_event`. The turn should contain the rendered prompt, turn number, and max turns. The session remains backend-owned because Codex, ACP, and Claude CLI will each need different internal state.

Alternatives considered:

- Replace `Codex.AppServer` with an ACP-shaped interface immediately. Rejected because Claude CLI does not currently require ACP, and Codex app-server is already a working baseline.
- Keep only a configurable command string. Rejected because command strings do not cover protocol startup, session continuation, event normalization, tool handling, timeout semantics, or resume behavior.

### Decision 2: Keep `Codex.AppServer` as protocol client, wrap it as a backend

Add `SymphonyElixir.AgentBackend.CodexAppServer` as the default backend. It delegates to the existing `SymphonyElixir.Codex.AppServer.start_session/2`, `run_turn/4`, and `stop_session/1`, then maps emitted messages into backend-neutral events while preserving Codex-specific fields.

`Codex.AppServer` should remain directly testable as the Codex protocol client. The wrapper owns the backend contract; the app-server module owns Codex protocol details.

Alternatives considered:

- Rename/move `Codex.AppServer` into `AgentBackend.CodexAppServer` in one step. Rejected because it would create a large file/test move with limited behavioral signal.
- Modify `Codex.AppServer` to implement the behaviour directly. Rejected because the existing function signatures accept Linear-shaped issue data and Codex-specific options; a thin wrapper creates a cleaner compatibility boundary.

### Decision 3: Resolve the backend through a small resolver with Codex default

Add a resolver module, for example `SymphonyElixir.AgentBackend.Resolver`, that returns the backend module for the current run. For this change, the resolver returns `AgentBackend.CodexAppServer` by default and may accept a test override via `AgentRunner` options.

Configuration migration to `agent_backend` is deferred. The resolver can later read a generalized config block without forcing this change to migrate existing `WORKFLOW.md` files.

Alternatives considered:

- Add full `agent_backend` config now. Rejected because the first useful change is the code boundary; config migration can follow once multiple backend implementations exist.
- Hard-code the wrapper in `AgentRunner`. Rejected because it would recreate the same coupling one module lower and complicate tests for future backends.

### Decision 4: Normalize events while preserving legacy Codex event compatibility

Backends should emit maps with at least:

- `:event`
- `:timestamp`
- `:backend`
- optional `:session_id`
- optional `:thread_id` / `:turn_id`
- optional `:worker_pid`
- optional `:usage`
- optional `:rate_limits`
- optional `:payload` / `:raw`

For this change, `AgentRunner` should forward normalized updates to the orchestrator under an agent-neutral message shape. To avoid breaking existing code abruptly, the orchestrator can either accept both `{:agent_worker_update, issue_id, update}` and `{:codex_worker_update, issue_id, update}` or `AgentRunner` can preserve the existing message shape while the update payload gains `:backend`. The preferred implementation is dual-compatible receive handling in the orchestrator, because it lets tests migrate incrementally and gives later backends a neutral path.

Alternatives considered:

- Rename all orchestrator state fields from `codex_*` to `agent_*` now. Rejected because it expands the change across dashboard/API snapshots and makes the first backend boundary harder to verify.
- Preserve only Codex event shapes. Rejected because non-Codex backends need a stable activity and telemetry contract.

### Decision 5: Keep token/rate-limit extraction permissive

The existing orchestrator already extracts token usage and rate-limit payloads from multiple nested shapes. That permissive extraction should remain available for normalized backend events. The wrapper should not discard raw payloads, because future backends will have different telemetry envelopes and dashboard/debugging code benefits from raw context.

Alternatives considered:

- Define one strict usage schema immediately. Rejected because backend telemetry differs and strictness would likely lose useful data during the transition.

### Decision 6: Keep dynamic tools Codex-specific for now

`linear_graphql` remains part of `Codex.DynamicTool` and the Codex app-server startup path in this change. The backend contract should not require all backends to support Codex dynamic tools. Future Work Channel changes should provide provider-neutral work operations through skills and CLI/scripts rather than making dynamic tools the portable backend surface.

Alternatives considered:

- Move `linear_graphql` into `AgentBackend` as a common backend feature. Rejected because ACP and Claude integrations will not necessarily expose the same dynamic tool protocol.

## Risks / Trade-offs

- Backend-neutral naming may coexist with `codex_*` dashboard fields for a while -> Keep compatibility aliases and document that broad field migration is deferred.
- The wrapper may become a pass-through that does not prove future backend viability -> Keep the behaviour and event contract explicit, and add tests using a fake backend through `AgentRunner`.
- Event normalization may hide Codex-specific data needed for debugging -> Preserve raw payloads and existing Codex-specific fields in the normalized event map.
- Config migration is deferred -> Existing users stay unblocked, but a later change must introduce and validate `agent_backend` config before non-Codex backends are operator-selectable.
- Claude and ACP backends may need callbacks not present in the initial behaviour -> Keep backend-owned session state opaque and avoid over-specifying transport-specific fields in the shared callbacks.

## Migration Plan

1. Add `AgentBackend` behaviour and lightweight shared types/docs.
2. Add `AgentBackend.CodexAppServer` wrapper around existing `Codex.AppServer`.
3. Add a resolver that defaults to `codex_app_server`.
4. Update `AgentRunner` to call the resolver/backend while preserving workspace hooks, prompt building, continuation turns, and error handling.
5. Add neutral event forwarding and orchestrator receive compatibility for agent events.
6. Keep Codex app-server tests in place, then add focused AgentRunner/backend tests using both the Codex wrapper and a fake backend.
7. Run existing test suites for app-server, core AgentRunner behavior, orchestrator status, dashboard snapshots, config, and specs.

Rollback is straightforward: revert `AgentRunner` to direct `Codex.AppServer` calls and remove the new wrapper/resolver modules. Because workflow configuration remains unchanged, no operator configuration rollback is required.

## Open Questions

- Should the first implementation send only `:agent_worker_update`, or accept both agent-neutral and legacy `:codex_worker_update` messages while tests migrate?
- Should the shared event field be named `:worker_pid`, `:process_pid`, or `:backend_pid`? The design prefers `:worker_pid` while preserving `:codex_app_server_pid`.
- Should `cancel/1` be added to the initial behaviour, or deferred until ACP/Claude integrations expose a concrete cancellation need?

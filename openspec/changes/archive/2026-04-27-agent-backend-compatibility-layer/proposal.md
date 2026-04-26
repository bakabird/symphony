## Why

Symphony currently runs coding agents through a Codex-specific app-server path, with Codex protocol, configuration, runtime events, stall detection, and dashboard fields coupled through the orchestrator. This blocks planned OpenCode and Claude Code support because those backends do not share one launch or session model.

This change introduces a backend-neutral compatibility layer first, so the existing Codex behavior can remain the baseline while later changes add ACP/OpenCode and Claude CLI implementations behind the same boundary.

## What Changes

- Add an `AgentBackend` runtime contract for starting logical sessions, running turns, stopping sessions, and emitting normalized runtime events.
- Route `AgentRunner` through a backend resolver instead of directly calling `SymphonyElixir.Codex.AppServer`.
- Wrap the existing Codex app-server integration as the default `codex_app_server` backend without changing the current `codex` workflow configuration behavior.
- Introduce backend-neutral runtime event semantics that preserve current session, usage, rate-limit, and activity information needed by the orchestrator.
- Keep existing Codex event and dashboard compatibility during this change; broad `codex_*` field renaming is deferred.
- Document that ACP/OpenCode and Claude Code stream integrations are future backend implementations, not part of this compatibility-layer change.

## Capabilities

### New Capabilities

- `agent-backend-runtime`: Defines backend-neutral agent execution requirements, event normalization, default Codex compatibility, and future backend extensibility expectations.

### Modified Capabilities

- None.

## Impact

- Affected code:
  - `elixir/lib/symphony_elixir/agent_runner.ex`
  - `elixir/lib/symphony_elixir/codex/app_server.ex`
  - new `elixir/lib/symphony_elixir/agent_backend*` modules
  - selected orchestrator event handling where needed to accept normalized backend events
  - tests covering AgentRunner, Codex app-server compatibility, config defaults, and dashboard activity accounting
- Compatibility:
  - Existing `codex` workflow configuration remains valid.
  - Existing Codex app-server startup, turn continuation, workspace, timeout, approval, dynamic tool, and event behavior remains the compatibility baseline.
- Deferred work:
  - Implementing `acp_stdio`, `opencode acp`, or `claude_cli_stream`.
  - Migrating workflow configuration from `codex` to a generalized `agent_backend` block.
  - Renaming dashboard/API fields from `codex_*` to `agent_*`.
  - Work Channel / `WorkItem` / `ProgressNote` engineering changes.

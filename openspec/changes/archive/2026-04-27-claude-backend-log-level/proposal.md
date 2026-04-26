## Why

Claude-backed runs already emit structured session events, but the project does not yet give operators a simple way to control how much Claude-related detail is written to the global logs. We need a Claude-specific logging gate so normal runs stay quiet while debugging can be turned up without affecting other backends.

## What Changes

- Add a Claude-backend-specific logging level controlled by an environment variable.
- Route Claude session lifecycle and stream events into the existing global application log when the level allows it.
- Keep the logging scope limited to Claude so other backends and orchestrator logs are unchanged.
- Preserve the current global log sink behavior so any enabled Claude logs still land in the shared log directory.

## Capabilities

### New Capabilities
- `claude-backend-logging`: Claude-specific logging control for session lifecycle and stream event visibility, including a runtime log-level gate.

### Modified Capabilities
- None

## Impact

- Affects `elixir/lib/symphony_elixir/agent_backend/claude_cli_stream.ex` and related Claude event logging paths.
- May add a Claude-specific environment variable read path in runtime configuration.
- Uses the existing rotating disk log sink configured by `SymphonyElixir.LogFile`.
- Requires regression coverage for level-gated Claude logging behavior and unchanged behavior for non-Claude paths.

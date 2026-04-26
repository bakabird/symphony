## Context

Claude backend runs already emit structured events into the orchestrator path, and the application already has a rotating global log sink. The missing piece is Claude-specific verbosity control: operators need to turn detailed Claude logging on and off without changing the behavior of other backends or the global logger configuration.

This change is scoped to the Claude backend only. The project already treats logging as an application-level concern, so the design should preserve the existing global sink and only decide which Claude messages are forwarded into it.

## Goals / Non-Goals

**Goals:**
- Add a Claude-specific verbosity gate driven by `SYMPHONY_CLAUDE_LOG_LEVEL`.
- Keep Claude session lifecycle and stream-event logs visible in the shared application log when enabled.
- Leave orchestrator, Codex, ACP, and other non-Claude logging behavior unchanged.
- Make the logging level decision deterministic for the duration of a Claude session.

**Non-Goals:**
- Do not change the global Logger backend or disk log configuration.
- Do not preserve raw Claude CLI transcript bytes.
- Do not introduce a new per-session file layout or a separate Claude-only log sink.
- Do not make this setting part of `WORKFLOW.md` or other repository workflow config.

## Decisions

### 1. Use a Claude-local verbosity helper instead of global Logger configuration
The Claude backend will read and interpret `SYMPHONY_CLAUDE_LOG_LEVEL` itself, then decide whether to emit each message into the normal `Logger` pipeline.

Rationale:
- The requirement is Claude-only control, not system-wide log tuning.
- Reusing the existing global application log sink keeps the implementation simple and preserves current log rotation behavior.
- Keeping the gate local avoids changing noise levels for orchestrator and other backend logs.

Alternatives considered:
- Reconfiguring Logger globally from the env var: rejected because it would affect unrelated subsystems.
- Moving the setting into `WORKFLOW.md`: rejected because this is operational logging policy, not workflow policy.

### 2. Read the environment variable once per Claude session
The backend will resolve the effective log level during `start_session/2` and store it in the session state for the lifetime of that backend session.

Rationale:
- Gives one consistent verbosity mode across all turns in the same run.
- Avoids repeated env lookups on every stream event.
- Keeps behavior stable even if the process environment changes mid-run.

Alternatives considered:
- Re-read on every event: rejected because it adds avoidable overhead and can make logs inconsistent within a single session.
- Read only at application startup: rejected because the setting is Claude-specific and should be scoped to the backend session, not the whole process.

### 3. Map Claude verbosity tiers to structured Logger calls
The backend will treat `off`, `info`, `debug`, and `trace` as Claude verbosity tiers and translate them into `Logger` calls for lifecycle and stream events.

Rationale:
- The project already writes structured application logs; the cleanest path is to feed Claude events into that same pipeline.
- `trace` is a Claude-specific verbosity tier, not a Logger backend mode, so the mapping can remain backend-local.
- Structured logging is sufficient for debugging and observability without raw transcript preservation.

Alternatives considered:
- Add raw transcript capture: rejected by scope and by the requirement to avoid transcript preservation.
- Use `Logger.metadata` only and rely on existing log statements: rejected because the Claude backend needs explicit control over which events are emitted at all.

### 4. Keep the scope limited to Claude backend event emission
Only Claude-related session lifecycle and stream-event logging will respond to `SYMPHONY_CLAUDE_LOG_LEVEL`.

Rationale:
- This matches the desired operational behavior and avoids unintended side effects elsewhere in the system.
- Non-Claude logs remain the responsibility of their own modules and existing severity choices.

Alternatives considered:
- Shared verbosity setting for all agent backends: rejected because it would couple unrelated backends and make log behavior harder to reason about.

## Risks / Trade-offs

- [Risk] Claude debug/trace output may be verbose enough to increase log volume significantly. → Mitigation: keep the gate local and default to `info`, with `off` available for quiet operation.
- [Risk] Invalid env values could lead to confusing behavior. → Mitigation: normalize unsupported values to `info` and keep the fallback deterministic.
- [Risk] Session-level caching means env changes do not take effect until a new Claude session starts. → Mitigation: document the behavior as session-scoped and predictable.

## Migration Plan

1. Ship the Claude verbosity helper and backend logging changes behind the new environment variable.
2. Default the env var to `info` so existing lifecycle visibility remains available without extra configuration.
3. Document `SYMPHONY_CLAUDE_LOG_LEVEL` as the only Claude-specific toggle.
4. If needed, operators can roll back by unsetting the variable or deploying the previous version; no data migration is required.

## Open Questions

- None at this time. The logging tiers, scope, and sink behavior are sufficiently defined for implementation.

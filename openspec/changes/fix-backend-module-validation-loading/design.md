## Context

`AgentRunner` currently validates a resolved backend module by calling `function_exported?/3` on callback function names. In Elixir, this check returns `false` when the module is not yet loaded, even if the module is valid and available on code paths. This causes false `ArgumentError` failures for configured backends like `SymphonyElixir.AgentBackend.ClaudeCliStream`, which then triggers orchestrator retry backoff loops.

The change is localized to backend validation and related tests, but it is operationally important because it can block all work dispatch for affected backends. Existing behavior for truly invalid backends must remain strict and explicit.

## Goals / Non-Goals

**Goals:**
- Ensure backend validation is load-aware and does not reject valid modules only because they are not loaded yet.
- Preserve strict contract enforcement that backends must provide `start_session/2`, `run_turn/3`, and `stop_session/1`.
- Provide clear error semantics separating module load failure from callback mismatch.
- Add regression tests that reproduce and prevent this failure mode.

**Non-Goals:**
- No changes to backend protocol implementation details (`codex_app_server`, `acp_stdio`, `claude_cli_stream` internals).
- No changes to orchestration retry policy or backoff timing.
- No workflow schema or configuration format changes.

## Decisions

### Decision 1: Explicitly ensure backend module load before export checks

`ensure_backend_module!/1` will perform an explicit module load check before callback introspection. Validation will only proceed to `function_exported?/3` checks after module load succeeds.

Rationale:
- Removes false negatives caused by unloaded modules.
- Keeps callback validation logic unchanged for loaded modules.

Alternatives considered:
- Call backend functions directly and rescue failures: rejected because it mixes interface validation with runtime side effects.
- Remove validation entirely and trust backend calls to fail naturally: rejected because it weakens error locality and diagnostic quality.

### Decision 2: Split failure modes for load failure vs callback mismatch

Backend validation will distinguish:
- Module cannot be loaded.
- Module loads but does not satisfy callback contract.

Rationale:
- Makes operator debugging and log interpretation faster.
- Prevents misleading “does not implement callbacks” errors when the real cause is loading.

Alternatives considered:
- Keep single generic error message: rejected because it obscures root cause.

### Decision 3: Add targeted regression tests around load-aware validation

Tests will cover:
- Valid backend module not preloaded before validation.
- Invalid backend atom/module that fails load.
- Loaded module missing required callbacks.

Rationale:
- Captures the precise failure mode seen in production logs.
- Prevents regressions as backend resolver behavior evolves.

Alternatives considered:
- Only integration testing through orchestration: rejected because failure is deterministic and better asserted in unit-level AgentRunner tests.

## Risks / Trade-offs

- [Risk] More explicit load checks may slightly increase validation overhead per run.  
  Mitigation: keep checks minimal and only in backend resolution path.

- [Risk] New error branching could break tests that assert previous generic error text.  
  Mitigation: update tests to assert stable semantics rather than brittle full strings.

- [Risk] Inconsistent module-loading behavior across environments may still surface edge cases.  
  Mitigation: include tests that exercise unloaded module behavior directly.

## Migration Plan

1. Update backend validation in `AgentRunner` to load modules before callback checks and emit differentiated errors.
2. Add/adjust tests in `agent_runner_test.exs` (and related backend tests if needed).
3. Run targeted test suite for backend validation paths.
4. Deploy as normal application update; no data migration required.

Rollback:
- Revert the validation change if regressions appear. This is code-only and does not require data rollback.

## Open Questions

- Should load failure expose raw `Code.ensure_loaded/1` reason details in user-facing errors, or keep detailed reason only in logs?
- Do we want a shared helper for load-aware behavior checks to enforce consistency across other runtime module validations?

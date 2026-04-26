## 1. Claude log level plumbing

- [x] 1.1 Add a Claude-specific log level parser or helper that reads `SYMPHONY_CLAUDE_LOG_LEVEL` and normalizes `off`, `info`, `debug`, and `trace`, defaulting invalid values to `info`.
- [x] 1.2 Thread the resolved Claude log level into `ClaudeCliStream` session state so the level is decided once per Claude session.

## 2. Claude event logging

- [x] 2.1 Gate Claude session lifecycle and stream-event logging by the resolved Claude log level while keeping the existing global Logger sink.
- [x] 2.2 Emit the intended level-specific Claude messages for `session_started`, `notification`, `turn_completed`, `turn_failed`, and related lifecycle events without affecting non-Claude logging.

## 3. Verification and docs

- [x] 3.1 Add regression tests for env var parsing, default fallback, and level-gated Claude logging behavior.
- [x] 3.2 Update operator-facing docs to describe `SYMPHONY_CLAUDE_LOG_LEVEL` and the supported verbosity levels.

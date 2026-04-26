# claude-backend-logging Specification

## Purpose
TBD - created by archiving change claude-backend-log-level. Update Purpose after archive.

## Requirements
### Requirement: Claude logging level is controlled by an environment variable
The system SHALL control Claude-backend log verbosity with `SYMPHONY_CLAUDE_LOG_LEVEL`.
The system SHALL treat valid values as `off`, `info`, `debug`, and `trace`.
If the variable is unset or invalid, the system SHALL default to `info`.

#### Scenario: Unset environment variable uses default
- **WHEN** the Claude backend starts and `SYMPHONY_CLAUDE_LOG_LEVEL` is not set
- **THEN** the system SHALL use `info` as the effective Claude logging level

#### Scenario: Invalid environment variable falls back safely
- **WHEN** the Claude backend starts and `SYMPHONY_CLAUDE_LOG_LEVEL` contains an unsupported value
- **THEN** the system SHALL use `info` as the effective Claude logging level

### Requirement: Claude backend logs are written to the global application log
The system SHALL emit Claude-backend log messages through the existing application logging pipeline so enabled Claude logs appear in the configured global log file.

#### Scenario: Enabled Claude logging appears in global logs
- **WHEN** Claude logging is enabled at any level other than `off`
- **THEN** the system SHALL write the selected Claude log messages to the shared application log sink

#### Scenario: Global log sink remains unchanged
- **WHEN** Claude logging is enabled
- **THEN** the system SHALL continue using the existing global log destination rather than a separate Claude-only sink

### Requirement: Claude logging scope is limited to the Claude backend
The system SHALL apply `SYMPHONY_CLAUDE_LOG_LEVEL` only to Claude-backend logging behavior.
The system SHALL NOT change the logging verbosity of unrelated backends or orchestrator logging.

#### Scenario: Non-Claude logs remain unaffected
- **WHEN** `SYMPHONY_CLAUDE_LOG_LEVEL` changes
- **THEN** the system SHALL keep non-Claude backend and orchestrator logging behavior unchanged

#### Scenario: Claude-only verbosity changes
- **WHEN** the Claude backend evaluates its logging level
- **THEN** only Claude session lifecycle and stream event logging SHALL respond to the environment variable

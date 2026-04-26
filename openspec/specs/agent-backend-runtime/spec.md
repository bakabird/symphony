# agent-backend-runtime Specification

## Purpose
TBD - created by archiving change agent-backend-compatibility-layer. Update Purpose after archive.

## Requirements
### Requirement: Agent runs use a backend runtime contract
The system SHALL execute agent sessions through an `AgentBackend` runtime contract instead of requiring `AgentRunner` to call a concrete Codex protocol module directly.

#### Scenario: AgentRunner starts a backend session
- **WHEN** an agent run has created its workspace and built the first turn prompt
- **THEN** AgentRunner starts a session through the resolved agent backend

#### Scenario: AgentRunner runs a turn through the backend
- **WHEN** a backend session has been started for an agent run
- **THEN** AgentRunner submits the rendered prompt to the backend as a turn request

#### Scenario: AgentRunner stops the backend session
- **WHEN** an agent run completes, fails, or exits after a backend session was started
- **THEN** AgentRunner stops the backend session before returning control to the orchestrator

### Requirement: The default backend preserves Codex app-server behavior
The system SHALL provide `codex_app_server` as the default backend and SHALL preserve existing Codex app-server workflow configuration and runtime behavior.

#### Scenario: Existing codex config remains valid
- **WHEN** `WORKFLOW.md` contains the existing `codex` configuration block
- **THEN** the default backend uses that configuration to launch and configure Codex app-server sessions

#### Scenario: Existing Codex turn continuation remains supported
- **WHEN** a work item remains in an active state after a successful turn and the run has not reached `agent.max_turns`
- **THEN** the default backend continues the run using the existing Codex app-server session semantics

#### Scenario: Existing Codex protocol behavior remains covered
- **WHEN** the default backend starts and runs a Codex app-server turn
- **THEN** the existing Codex startup handshake, sandbox policy, approval handling, dynamic tool handling, timeout handling, and completion/error mapping remain compatible with current behavior

### Requirement: Backend sessions are logical sessions
The system SHALL treat backend sessions as opaque logical session handles owned by the backend implementation.

#### Scenario: Long-lived protocol backend keeps process state
- **WHEN** a backend maintains a long-lived subprocess or protocol connection across turns
- **THEN** the backend stores that process or connection state inside its opaque session handle

#### Scenario: Command-stream backend can resume logically
- **WHEN** a backend represents a logical session using repeated command invocations and resume metadata
- **THEN** the backend stores the resume metadata inside its opaque session handle without requiring AgentRunner to know the transport details

### Requirement: Backends emit normalized runtime events
The system SHALL allow each backend to emit normalized runtime event maps that include backend identity, event name, timestamp, and any available session, turn, process, usage, rate-limit, payload, or raw-message data.

#### Scenario: Backend emits session activity
- **WHEN** a backend starts a turn or receives turn activity from the agent process
- **THEN** it emits a runtime event that includes `event`, `timestamp`, and `backend`

#### Scenario: Backend emits session identifiers
- **WHEN** a backend can identify a logical session or turn
- **THEN** it includes the session or turn identifiers in the normalized runtime event

#### Scenario: Backend emits telemetry
- **WHEN** a backend receives token usage or rate-limit telemetry
- **THEN** it includes that telemetry in the normalized runtime event without discarding the raw payload

### Requirement: Orchestrator consumes backend-neutral activity
The orchestrator SHALL accept backend-neutral agent runtime updates for active work and SHALL use those updates for last activity, session identity, turn count, token accounting, rate-limit state, and dashboard refreshes.

#### Scenario: Runtime update refreshes last activity
- **WHEN** the orchestrator receives a normalized runtime event for a running work item
- **THEN** it updates the running entry's last activity timestamp from that event

#### Scenario: Runtime update captures session identity
- **WHEN** the orchestrator receives a normalized runtime event with a session identifier
- **THEN** it stores that session identifier on the running entry

#### Scenario: Runtime update captures token usage
- **WHEN** the orchestrator receives a normalized runtime event with token usage
- **THEN** it applies the token delta to the running entry and aggregate totals

#### Scenario: Runtime update captures rate limits
- **WHEN** the orchestrator receives a normalized runtime event with rate-limit data
- **THEN** it updates the runtime rate-limit snapshot exposed to observability surfaces

### Requirement: Legacy Codex observability remains compatible
The system SHALL preserve existing Codex-oriented observability fields and messages while backend-neutral events are introduced.

#### Scenario: Existing dashboard fields remain available
- **WHEN** a Codex app-server run emits runtime activity through the default backend
- **THEN** existing dashboard and snapshot consumers can still read the current Codex-oriented fields for session, event, token, and process information

#### Scenario: Existing Codex update messages remain accepted during migration
- **WHEN** an existing test or runtime path sends a legacy Codex worker update message
- **THEN** the orchestrator continues to accept it and update running activity as before

### Requirement: Unsupported backend implementations are out of this change
The system SHALL NOT require OpenCode, ACP, Claude Code, or other non-Codex backend implementations as part of the compatibility-layer change.

#### Scenario: Non-Codex backend work is deferred
- **WHEN** the compatibility layer is implemented
- **THEN** `codex_app_server` is the only required production backend implementation

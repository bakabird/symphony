## ADDED Requirements

### Requirement: Backend validation SHALL be load-aware
The system SHALL load the resolved backend module before evaluating whether required `AgentBackend` callbacks are exported.

#### Scenario: Valid backend is not preloaded
- **WHEN** a backend module is resolvable but not yet loaded at validation time
- **THEN** the system SHALL load the module and continue callback contract validation instead of rejecting it as unsupported

### Requirement: Backend validation SHALL enforce callback contract after load
After successful module loading, the system SHALL require the backend module to export `start_session/2`, `run_turn/3`, and `stop_session/1`.

#### Scenario: Loaded backend has all required callbacks
- **WHEN** the resolved backend module is loaded and exports all required callbacks
- **THEN** backend validation SHALL accept the module and allow the agent run to proceed

#### Scenario: Loaded backend is missing required callbacks
- **WHEN** the resolved backend module is loaded but lacks one or more required callbacks
- **THEN** backend validation SHALL fail with an explicit callback-contract error

### Requirement: Backend validation failures SHALL distinguish load failure from contract failure
The system SHALL provide distinct failure semantics for module-load failure and callback-contract mismatch.

#### Scenario: Backend module cannot be loaded
- **WHEN** the resolved backend module cannot be loaded
- **THEN** backend validation SHALL fail with an explicit module-loading error that is distinguishable from callback mismatch

#### Scenario: Backend module loads but is invalid
- **WHEN** the resolved backend module loads successfully but does not satisfy callback requirements
- **THEN** backend validation SHALL fail with a callback-contract error and SHALL NOT report it as a load failure

### Requirement: Regression coverage SHALL protect load-aware validation behavior
Automated tests SHALL cover load-aware backend validation behavior for valid unloaded modules and invalid modules.

#### Scenario: Test suite verifies unloaded valid backend
- **WHEN** backend validation tests run with a valid backend module that is not preloaded
- **THEN** tests SHALL assert that validation succeeds after module loading

#### Scenario: Test suite verifies invalid backend handling
- **WHEN** backend validation tests run with invalid backend modules
- **THEN** tests SHALL assert distinct failure behavior for load failures and callback mismatches

## ADDED Requirements

### Requirement: Workflow defines validation levels and evidence types

The system SHALL allow `WORKFLOW.md` configuration to define named validation levels separately from supported evidence types.

#### Scenario: Parse configured validation levels

- **WHEN** workflow configuration includes validation levels for compile, launch, reproduce, and changed_flow
- **THEN** the system exposes those levels through normalized runtime configuration

#### Scenario: Parse configured evidence types

- **WHEN** workflow configuration includes evidence types for none, logs, screenshot, and video
- **THEN** the system exposes those evidence types through normalized runtime configuration

#### Scenario: Attach evidence types to validation levels

- **WHEN** a validation rule requires a level with an evidence type
- **THEN** resolved validation guidance keeps the level name and evidence type as separate fields

#### Scenario: Reject invalid unavailable behavior

- **WHEN** a validation level declares an unsupported unavailable behavior
- **THEN** workflow configuration parsing fails with an operator-visible invalid configuration error

### Requirement: Workflow maps Linear labels to validation guidance

The system SHALL allow validation rules to match Linear issue labels and resolve the required validation levels and evidence types for a specific ticket.

#### Scenario: Match ticket labels

- **WHEN** a ticket has a label matched by a validation rule
- **THEN** the resolved validation guidance includes the validation levels and evidence types required by that rule

#### Scenario: Match labels case-insensitively

- **WHEN** a Linear issue label differs from a configured label only by case or surrounding whitespace
- **THEN** the validation rule still matches that label

#### Scenario: Use loosest default rule when no rule matches

- **WHEN** no validation rule matches a ticket
- **THEN** the resolved validation guidance uses the configured loosest default rule

#### Scenario: Use loosest default rule when labels are missing

- **WHEN** a ticket has no Linear labels
- **THEN** the resolved validation guidance uses the configured loosest default rule

#### Scenario: Use loosest default rule when labels are non-standard

- **WHEN** a ticket has labels that are not part of any configured validation rule
- **THEN** the resolved validation guidance uses the configured loosest default rule

#### Scenario: Preserve configured rule order

- **WHEN** multiple validation rules could match a ticket
- **THEN** the resolved validation guidance uses the first matching rule in workflow order

### Requirement: Prompt includes resolved validation guidance

The system SHALL include resolved validation guidance in the prompt rendering context for each agent turn.

#### Scenario: Render matched validation guidance

- **WHEN** a prompt template references the resolved validation guidance
- **THEN** the rendered prompt includes the matched rule summary, required validation levels, and required evidence types for the current ticket

#### Scenario: Render level commands

- **WHEN** a required validation level defines a command
- **THEN** the rendered prompt includes that command as expected validation activity for the agent to run or report as unavailable

### Requirement: Workpad records validation evidence by required level

The workflow instructions SHALL require the agent workpad to record each required validation level, the required evidence type for that level, the evidence captured, and any unavailable reason or residual risk.

#### Scenario: Record completed evidence

- **WHEN** the agent completes a required validation level
- **THEN** the workpad validation section records the level, required evidence type, captured evidence, and result

#### Scenario: Record unavailable runtime evidence

- **WHEN** a required runtime or media level cannot be completed in the current environment
- **THEN** the workpad validation section records the unavailable reason and residual risk instead of marking the evidence as completed

### Requirement: Ticket-authored validation remains mandatory

The system SHALL treat ticket-authored `Validation`, `Test Plan`, and `Testing` requirements as additive to the resolved validation guidance.

#### Scenario: Ticket validation adds requirements

- **WHEN** a ticket includes an explicit validation or test plan section
- **THEN** the agent is instructed to add those requirements to the workpad and complete them in addition to resolved validation levels

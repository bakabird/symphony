## ADDED Requirements

### Requirement: Workflow Review state routing
The system SHALL support a non-active Linear state named `Workflow Review` between agent implementation and human review.

#### Scenario: Workflow Review is non-active
- **WHEN** workflow configuration defines active tracker states
- **THEN** `Workflow Review` SHALL NOT be included in `tracker.active_states`

#### Scenario: Completed implementation enters Workflow Review
- **WHEN** an agent completes implementation, validation, PR creation or update, and handoff notes without requiring human intervention
- **THEN** the agent SHALL move the Linear issue to `Workflow Review` instead of `Human Review`

#### Scenario: Human handoff exception
- **WHEN** the agent determines that missing access, conflicting requirements, task defects, scope risk, or product judgment prevents responsible continuation
- **THEN** the agent MAY move the issue directly to `Human Review` with a concise handoff brief in the workpad

### Requirement: Automatic review workflow gate
The system SHALL use the automatic GitHub PR review workflow as the normal driver for transitions out of `Workflow Review`.

#### Scenario: Gate only acts from Workflow Review
- **WHEN** the automatic review gate completes for a PR linked to a Linear issue whose current state is not `Workflow Review`
- **THEN** the gate SHALL NOT change the Linear issue state

#### Scenario: Clean or low-only review advances to Human Review
- **WHEN** the automatic review gate evaluates a Linear issue in `Workflow Review` and finds no unresolved prReviewer medium/high findings
- **THEN** the gate SHALL move the Linear issue to `Human Review`

#### Scenario: Blocking review returns to Todo
- **WHEN** the automatic review gate evaluates a Linear issue in `Workflow Review` and finds unresolved prReviewer medium or high findings
- **THEN** the gate SHALL move the Linear issue to `Todo`

#### Scenario: Manual review does not drive Linear
- **WHEN** a comment-triggered prReviewer workflow posts findings or updates prReviewer state
- **THEN** that manual review SHALL NOT move the Linear issue between `Workflow Review`, `Todo`, or `Human Review`

### Requirement: Gate failure behavior
The automatic review gate SHALL fail closed for infrastructure, mapping, parsing, or review execution failures.

#### Scenario: Missing Linear linkback
- **WHEN** the gate cannot find a Linear linkback comment on the PR
- **THEN** the gate SHALL NOT change Linear state and SHALL record a diagnostic in PR-visible gate output when possible

#### Scenario: Invalid prReviewer state
- **WHEN** the gate cannot read or parse required prReviewer gate state
- **THEN** the gate SHALL leave the Linear issue in `Workflow Review`

#### Scenario: Review infrastructure failure
- **WHEN** prReviewer fails, is cancelled, times out, or GitHub review-thread data cannot be read
- **THEN** the gate SHALL leave the Linear issue in `Workflow Review` and report the failure as diagnostic output

#### Scenario: Linear update failure
- **WHEN** the gate determines a target Linear state but cannot update Linear
- **THEN** the gate SHALL NOT attempt an alternate guessed transition and SHALL report the Linear API failure

### Requirement: PR to Linear issue mapping
The automatic review gate SHALL map a GitHub PR to its Linear issue using Linear's GitHub linkback comment as the primary source.

#### Scenario: Parse Linear linkback
- **WHEN** a PR issue comment contains `<!-- linear-linkback -->` and a Linear issue URL
- **THEN** the gate SHALL parse the Linear issue identifier from that comment

#### Scenario: Avoid branch-name guesses
- **WHEN** the Linear linkback comment is unavailable
- **THEN** the gate SHALL NOT use branch name or PR title as a primary mapping source for state changes

### Requirement: Authoritative full PR review dispatch
The automatic review workflow SHALL support an explicit `workflow_dispatch` path that runs an authoritative full-PR prReviewer review for a specific PR head.

#### Scenario: Agent dispatches review after entering Workflow Review
- **WHEN** the agent has pushed the PR branch and moved the Linear issue to `Workflow Review`
- **THEN** the agent SHALL trigger the automatic review workflow with the PR number and expected head SHA

#### Scenario: Dispatch verifies head SHA
- **WHEN** a workflow-dispatched review starts with an expected head SHA
- **THEN** the workflow SHALL verify the PR current head SHA matches before using the review result for gate transitions

#### Scenario: Full PR review scope
- **WHEN** the workflow-dispatched review runs for Workflow Review gating
- **THEN** prReviewer SHALL review the full PR diff rather than only an incremental commit range

### Requirement: prReviewer gate state contract
prReviewer SHALL maintain machine-readable gate state in the existing `pr-reviewer-state` comment and SHALL keep fallback findings current per review run.

#### Scenario: Extend existing state comment
- **WHEN** prReviewer completes a gate-relevant automatic review
- **THEN** it SHALL update the existing `<!-- pr-reviewer-state ... -->` comment with current gate data instead of creating a separate gate-state comment

#### Scenario: Current fallback findings overwrite history
- **WHEN** prReviewer generates fallback findings that could not be posted inline
- **THEN** `pr-reviewer-state` SHALL contain the current fallback findings for that run and SHALL NOT require gate consumers to parse historical fallback comments

#### Scenario: Single fallback summary
- **WHEN** prReviewer needs to show fallback findings to humans
- **THEN** it SHALL create or update one human-readable fallback summary comment identified by a stable marker

#### Scenario: Severity counts are machine-readable
- **WHEN** prReviewer updates gate state
- **THEN** the gate state SHALL include machine-readable severity information sufficient to distinguish high, medium, low, and unparseable findings

### Requirement: Gate finding evaluation
The automatic review gate SHALL evaluate only prReviewer-produced findings and SHALL treat medium/high or unparseable prReviewer findings as blocking.

#### Scenario: Ignore non-prReviewer comments
- **WHEN** unresolved review comments exist from humans or other bots
- **THEN** the Workflow Review gate SHALL NOT count them as prReviewer gate findings

#### Scenario: Resolved prReviewer inline thread
- **WHEN** a prReviewer inline review thread is resolved
- **THEN** the Workflow Review gate SHALL ignore that thread for blocking-severity decisions

#### Scenario: Unresolved low-only findings
- **WHEN** all current unresolved prReviewer findings are low severity
- **THEN** the Workflow Review gate SHALL consider the review non-blocking

#### Scenario: Unresolved medium or high finding
- **WHEN** any current unresolved prReviewer finding is medium or high severity
- **THEN** the Workflow Review gate SHALL consider the review blocking

#### Scenario: Unparseable prReviewer severity
- **WHEN** the gate cannot parse the severity of a prReviewer finding that otherwise appears gate-relevant
- **THEN** the Workflow Review gate SHALL treat the finding as blocking

### Requirement: Workflow Review handoff
When blocking prReviewer feedback returns a Linear issue to `Todo`, the gate SHALL update the persistent workpad with a Workflow Review handoff.

#### Scenario: Handoff records blocking summary
- **WHEN** the gate moves a Linear issue from `Workflow Review` to `Todo`
- **THEN** it SHALL update or create the issue's `## Codex Workpad` comment with a `Workflow Review Handoff` section summarizing blocking prReviewer findings

#### Scenario: GitHub remains source of truth
- **WHEN** the handoff section lists blocking findings
- **THEN** the handoff SHALL instruct the next agent to re-read GitHub review threads and `pr-reviewer-state` as the source of truth before making changes

#### Scenario: Reuse single workpad
- **WHEN** a `## Codex Workpad` comment already exists
- **THEN** the gate SHALL update that comment instead of creating a second workpad comment

### Requirement: Agent review-fix re-entry
An agent dispatched after `Workflow Review` returns an issue to `Todo` SHALL address blocking prReviewer feedback before returning the issue to review.

#### Scenario: Todo re-entry with attached PR
- **WHEN** an issue in `Todo` has an attached PR and a Workflow Review handoff
- **THEN** the agent SHALL move the issue to `In Progress`, fetch unresolved prReviewer review threads, read prReviewer gate fallback findings, and add each blocking item to the workpad checklist

#### Scenario: Resolve addressed inline thread
- **WHEN** the agent fixes or explicitly pushes back on an unresolved prReviewer medium/high inline thread
- **THEN** the agent SHALL reply in that thread with a `[codex]` explanation and resolve the thread

#### Scenario: Human decision required
- **WHEN** a prReviewer finding requires human product judgment, conflicts with task requirements, or cannot be responsibly resolved by the agent
- **THEN** the agent SHALL leave the relevant thread unresolved and move the issue to `Human Review` with a handoff brief

#### Scenario: Return to Workflow Review after feedback handling
- **WHEN** the agent has handled blocking prReviewer feedback without requiring human intervention
- **THEN** the agent SHALL push any changes and move the issue back to `Workflow Review` for another automatic full-PR review

### Requirement: Rework remains full reset
The system SHALL preserve `Rework` as a human-directed full approach reset state and SHALL NOT use it for normal prReviewer feedback loops.

#### Scenario: Blocking prReviewer feedback avoids Rework
- **WHEN** the Workflow Review gate finds medium/high prReviewer feedback
- **THEN** it SHALL move the issue to `Todo` rather than `Rework`

#### Scenario: Human-directed Rework
- **WHEN** a human moves an issue to `Rework`
- **THEN** the existing full reset behavior remains applicable, including closing the existing PR, removing the workpad, creating a fresh branch, and restarting the kickoff flow

### Requirement: Setup documentation
The setup documentation SHALL identify `Workflow Review` as a required non-standard Linear state and explain its gate behavior.

#### Scenario: Required state listed
- **WHEN** a user reads the Elixir setup documentation
- **THEN** `Workflow Review` SHALL be listed alongside the other required non-standard Linear statuses

#### Scenario: State behavior documented
- **WHEN** a user reads the workflow documentation
- **THEN** it SHALL explain that `Workflow Review` is non-active, normal agent completion enters it, automatic prReviewer gate moves clean or low-only results to `Human Review`, and blocking medium/high results return to `Todo`

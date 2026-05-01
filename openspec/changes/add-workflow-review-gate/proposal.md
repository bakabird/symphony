## Why

The current Symphony workflow sends completed agent work directly from `In Progress` to `Human Review`, so AI review is either manual or folded into the agent's own PR feedback sweep. We need a separate non-active review gate so GitHub Actions can run prReviewer, decide whether feedback is blocking, and route the Linear issue without dispatching another local agent during review.

## What Changes

- Add a non-active Linear state named `Workflow Review` between `In Progress` and `Human Review`.
- Change the normal completion path so agents move finished work to `Workflow Review` instead of directly to `Human Review`.
- Add an external GitHub Actions gate, driven by the automatic PR review workflow, that moves issues from `Workflow Review` to:
  - `Human Review` when prReviewer findings are clean or low-only.
  - `Todo` when unresolved prReviewer findings include medium/high feedback.
  - no new state when review infrastructure, GitHub mapping, Linear mapping, or gate parsing fails.
- Require the gate to map PRs to Linear issues through Linear's GitHub linkback comment and fail closed when the mapping is missing.
- Extend prReviewer integration expectations so machine-readable gate state is stored in the existing `pr-reviewer-state` comment and human-readable fallback findings are kept in a single updatable fallback summary comment.
- Add a `full_pr` prReviewer trigger for authoritative Workflow Review runs invoked through `workflow_dispatch`.
- Update the agent workflow contract so `Todo` re-entry from `Workflow Review` drives the agent to fetch unresolved prReviewer review threads, read prReviewer gate fallback findings, address or explicitly push back on each blocking item, resolve addressed prReviewer threads, and return to `Workflow Review` unless human intervention is required.
- Preserve `Rework` as a human-directed full-reset state; prReviewer medium/high feedback returns to `Todo`, not `Rework`.

## Capabilities

### New Capabilities
- `workflow-review-gate`: Defines the Workflow Review state, external prReviewer gate behavior, Linear state transitions, prReviewer gate-state contract, and agent re-entry requirements.

### Modified Capabilities

## Impact

- Affected workflow contract: `elixir/WORKFLOW.md` and project-level copied `WORKFLOW.md` files.
- Affected documentation: `elixir/README.md` setup guidance for required Linear statuses and review workflow behavior.
- Affected GitHub workflow examples: automatic PR review workflow gains `workflow_dispatch`, `full_pr` review support, and a Linear gate step.
- Affected prReviewer integration: action inputs/trigger handling, `pr-reviewer-state` schema, and fallback summary comment lifecycle.
- Affected agent behavior: completion state transition, review feedback sweep, Todo re-entry semantics, and GitHub review thread resolution expectations.
- External dependencies: GitHub Actions, GitHub GraphQL review thread APIs, Linear GraphQL issue/comment/state APIs, and repository secrets for Linear and prReviewer workflows.

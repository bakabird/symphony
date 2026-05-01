## 1. Workflow Contract

- [x] 1.1 Update `elixir/WORKFLOW.md` to add `Workflow Review` as a non-active state between `In Progress` and `Human Review`.
- [x] 1.2 Remove direct normal-completion transitions from `In Progress` to `Human Review`; require completed work to move to `Workflow Review`.
- [x] 1.3 Add the `Workflow Review` status map entry describing external GitHub Actions ownership and no local agent dispatch.
- [x] 1.4 Update the completion bar so agents dispatch the automatic review workflow after pushing the PR and moving the issue to `Workflow Review`.
- [x] 1.5 Add the Todo re-entry flow for issues returned from `Workflow Review`, including unresolved prReviewer thread fetching, fallback finding handling, `[codex]` replies, thread resolution, validation, push, and return to `Workflow Review`.
- [x] 1.6 Preserve direct `Human Review` only for blocker, ambiguity, task defect, missing access, or human-decision handoff cases.
- [x] 1.7 Ensure `Rework` remains documented as a human-directed full-reset state and is not used for normal prReviewer medium/high feedback.

## 2. Documentation

- [x] 2.1 Update `elixir/README.md` to list `Workflow Review` as a required non-standard Linear state.
- [x] 2.2 Document that `Workflow Review` must not be included in `tracker.active_states`.
- [x] 2.3 Document the automatic gate transitions: low-only or clean to `Human Review`, medium/high to `Todo`, infra or mapping failure remains in `Workflow Review`.
- [x] 2.4 Document required repository secrets and setup expectations for the automatic review gate, including Linear API access.

## 3. prReviewer Contract

- [x] 3.1 Add a `full_pr` trigger to prReviewer that reviews the full PR diff for a resolved PR number.
- [x] 3.2 Add prReviewer action inputs for `pr_number` and `expected_head_sha`.
- [x] 3.3 Verify `expected_head_sha` before a workflow-dispatched full-PR review can update gate-relevant state.
- [x] 3.4 Extend the existing `pr-reviewer-state` comment schema with gate status, severity counts, current fallback findings, and diagnostic errors.
- [x] 3.5 Keep fallback findings current by overwriting them in `pr-reviewer-state` on each gate-relevant run.
- [x] 3.6 Replace one-off fallback issue comments with a single updatable human-readable fallback summary comment identified by a stable marker.
- [x] 3.7 Add prReviewer tests for `full_pr`, state schema updates, fallback state overwrite, fallback summary update, and expected-head mismatch behavior.

## 4. Automatic Workflow Gate

- [x] 4.1 Update the automatic PR review workflow to support `workflow_dispatch` with `pr_number` and `expected_head_sha` inputs.
- [x] 4.2 Add a target-repository gate step after prReviewer in the automatic workflow only.
- [x] 4.3 Implement PR-to-Linear mapping from the Linear linkback comment and fail closed when the linkback is missing.
- [x] 4.4 Fetch GitHub review threads through GraphQL so `isResolved` is available for inline prReviewer comments.
- [x] 4.5 Filter gate findings to prReviewer-produced feedback only, ignoring human and unrelated bot comments.
- [x] 4.6 Treat unresolved medium/high and unparseable prReviewer findings as blocking; treat low-only and clean reviews as non-blocking.
- [x] 4.7 Read current fallback findings from `pr-reviewer-state.gate.fallback_findings` and exclude historical fallback comments from gate decisions.
- [x] 4.8 Guard all Linear transitions so they occur only when the issue is currently in `Workflow Review`.
- [x] 4.9 Move `Workflow Review` to `Human Review` for clean or low-only review results.
- [x] 4.10 Move `Workflow Review` to `Todo` for blocking prReviewer findings.
- [x] 4.11 Leave the issue in `Workflow Review` and write diagnostics for review failure, GitHub data failure, malformed state, missing Linear linkback, or Linear API failure.

## 5. Linear Workpad Handoff

- [x] 5.1 Implement Linear GraphQL lookup for the issue's existing active `## Codex Workpad` comment.
- [x] 5.2 Update the existing workpad comment instead of creating a duplicate when a workpad exists.
- [x] 5.3 Create a workpad comment only when no active `## Codex Workpad` comment exists.
- [x] 5.4 Add or replace a `Workflow Review Handoff` section containing PR URL, gate source, checked timestamp, blocking inline thread summary, fallback finding summary, and required agent actions.
- [x] 5.5 State in the handoff that GitHub review threads and `pr-reviewer-state` remain the source of truth.

## 6. Validation

- [x] 6.1 Add or update tests for workflow prompt rendering to cover `Workflow Review`, Todo re-entry, and direct-Human-Review exception wording.
- [x] 6.2 Add tests for gate decision logic covering clean, low-only, medium/high, unparseable severity, resolved threads, fallback findings, and non-prReviewer comments.
- [x] 6.3 Add tests for Linear linkback parsing and fail-closed behavior when mapping is missing.
- [x] 6.4 Add tests for workpad handoff update/create behavior.
- [x] 6.5 Run targeted Elixir tests for workflow/config/prompt behavior.
- [x] 6.6 Run targeted prReviewer tests for the new action trigger and state-comment behavior.
- [x] 6.7 Run full relevant validation for each touched repository before handoff.

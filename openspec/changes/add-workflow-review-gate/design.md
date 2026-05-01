## Context

Symphony's Elixir workflow currently treats `Human Review` as the normal handoff after agent implementation. The more complete workflow template in `elixir/WORKFLOW.md` already has a PR feedback sweep, but it still assumes the agent can move directly to `Human Review` after checks and feedback handling. The desired flow inserts a non-active `Workflow Review` state where GitHub Actions runs prReviewer and an external gate decides the next Linear state.

The runtime distinction matters: Symphony's orchestrator dispatches only states listed in `tracker.active_states`. `Workflow Review` must stay out of that list so no local agent is dispatched while the review workflow runs. The GitHub Actions gate becomes the only normal path from `Workflow Review` to `Human Review`, while medium/high prReviewer findings return the issue to `Todo` so the ordinary Symphony polling loop can dispatch an agent to address review feedback.

This change spans three systems:

- Symphony workflow contract and documentation in this repository.
- prReviewer behavior and state comments in the review action repository.
- Target repository GitHub workflow steps that run prReviewer, interpret the result, and update Linear.

## Goals / Non-Goals

**Goals:**

- Add `Workflow Review` as a required, non-active Linear state between implementation and human review.
- Ensure agents normally move completed work to `Workflow Review`, not `Human Review`.
- Let only the automatic PR review workflow drive normal `Workflow Review` transitions.
- Route clean or low-only prReviewer results to `Human Review`.
- Route medium/high prReviewer results to `Todo`, with a workpad handoff that tells the next agent how to address unresolved prReviewer feedback.
- Preserve a human handoff escape hatch for ambiguity, task defects, missing permissions/secrets, or review feedback that requires human judgment.
- Make prReviewer fallback findings machine-readable through the existing `pr-reviewer-state` comment and human-readable through one updatable fallback summary comment.
- Add an authoritative `full_pr` prReviewer trigger for `workflow_dispatch` review runs.

**Non-Goals:**

- Do not make `Workflow Review` an active Symphony dispatch state.
- Do not make manual `@momo ...` comment-triggered reviews move Linear state.
- Do not make the Workflow Review gate responsible for CI/check green status or merge eligibility.
- Do not repurpose `Rework` for normal prReviewer feedback; `Rework` remains a human-directed full-reset state.
- Do not embed Linear-specific state transition behavior inside prReviewer's core review action.

## Decisions

### Decision: `Workflow Review` is non-active

`Workflow Review` will not be listed in `tracker.active_states`. Symphony will stop or avoid dispatching agents for that state, and GitHub Actions will own review-time automation.

Alternative considered: make `Workflow Review` active and let Symphony dispatch an agent to inspect review comments. This was rejected because the review behavior is intentionally delegated to GitHub Actions and prReviewer; dispatching a local agent would blur the state responsibility and make review-time automation harder to reason about.

### Decision: agent completion targets `Workflow Review`

The normal agent success path becomes `In Progress -> Workflow Review`. Agents may move directly to `Human Review` only for explicit handoff exceptions, such as missing auth, required human judgment, conflicting acceptance criteria, task defects, or scope/risk decisions the agent cannot responsibly make.

Alternative considered: allow agents to move directly to `Human Review` after they believe review feedback is handled. This was rejected for the normal path because it bypasses the external review gate.

### Decision: automatic workflow is the only normal gate driver

Only the automatic PR review workflow may drive `Workflow Review -> Human Review` or `Workflow Review -> Todo`. Manual comment-triggered prReviewer workflows remain investigation tools and do not update Linear state.

Alternative considered: let both automatic and manual review workflows drive Linear. This was rejected because identical-looking prReviewer comments would have different state consequences depending on trigger source, creating confusing and fragile behavior.

### Decision: use `workflow_dispatch` plus `full_pr` for authoritative gate runs

After pushing the finished PR, the agent moves the issue to `Workflow Review` and explicitly dispatches the automatic review workflow with `pr_number` and `expected_head_sha`. The workflow verifies the PR head and runs a full-PR review, avoiding the race where a `pull_request.synchronize` review completes before Linear enters `Workflow Review`.

The prReviewer action will expose a generic `full_pr` trigger. The trigger is review-scope terminology, not Linear workflow terminology; the Linear-specific interpretation remains in the target repository gate step.

Alternative considered: rely only on `pull_request.synchronize`. This was rejected because the gate is guarded to act only when Linear is already in `Workflow Review`, so a fast review run could no-op before the agent changes state.

### Decision: PR-to-Linear mapping uses Linear linkback comments

The gate will map a PR to a Linear issue by reading the Linear GitHub app linkback comment (`<!-- linear-linkback -->`) and parsing the Linear issue identifier from its URL/summary. If the mapping is missing, the gate fails closed: it does not change Linear state and records a diagnostic in PR state/comment output when possible.

Alternative considered: parse branch names or PR titles as the primary mapping. This was rejected because retries, fresh branches, and manual renames make those less trustworthy than Linear's own linkback.

### Decision: gate inputs are unresolved prReviewer inline threads plus current fallback findings

The gate uses GitHub GraphQL review threads to read `isResolved` and filters to prReviewer-authored inline feedback. Unresolved medium/high prReviewer inline threads are blocking; low-only threads are non-blocking. Unparseable prReviewer severities fail closed as blocking.

Fallback findings are not represented as GitHub review threads and cannot be resolved. prReviewer will therefore write current fallback findings into the existing `pr-reviewer-state` JSON, and each run overwrites that list. Historical fallback issue comments are not gate inputs.

Alternative considered: parse all historical fallback issue comments. This was rejected because issue comments have no resolved lifecycle and would cause old findings to block indefinitely.

### Decision: prReviewer owns stable state comments, target workflow owns Linear transitions

prReviewer extends the existing `<!-- pr-reviewer-state ... -->` comment with gate data such as severity counts, current fallback findings, status, and errors. prReviewer also maintains a single human-readable `<!-- pr-reviewer-fallback-summary -->` comment for fallback findings, updating it instead of creating a new one per run.

The target repository workflow step reads that state, reads unresolved review threads, updates the Linear workpad, and changes Linear state. This keeps prReviewer reusable outside Symphony/Linear workflows.

### Decision: medium/high feedback returns to `Todo`

When the gate finds blocking prReviewer feedback, it moves the issue from `Workflow Review` to `Todo`, not `Rework`. The next Symphony poll dispatches an agent. The workflow prompt instructs the agent to move the issue to `In Progress`, fetch unresolved prReviewer threads and fallback findings, fix or explicitly push back on each item, reply with `[codex]`, resolve addressed prReviewer threads, push changes, and return to `Workflow Review`.

`Rework` remains reserved for human-directed full approach resets that close the old PR, remove the workpad, create a fresh branch, and restart.

## Risks / Trade-offs

- [Risk] The gate may race with human state changes or unrelated PR pushes. → Mitigation: gate transitions only when the Linear issue is currently `Workflow Review`, and dispatch runs verify the expected PR head SHA.
- [Risk] Missing Linear linkback comments prevent PR-to-issue mapping. → Mitigation: fail closed, leave the issue unchanged, and record a diagnostic instead of guessing from branch or title.
- [Risk] prReviewer fallback findings have no GitHub resolved lifecycle. → Mitigation: make the current fallback list part of the overwritten `pr-reviewer-state` schema and keep historical fallback comments out of gate decisions.
- [Risk] Agents could silently resolve review threads without accountability. → Mitigation: workflow instructions require a `[codex]` reply explaining the fix or pushback before resolving a prReviewer thread.
- [Risk] Manual prReviewer runs may produce comments that look gate-relevant. → Mitigation: only the automatic workflow gate changes Linear state; manual runs are explicitly non-driving.
- [Risk] Infrastructure failures could accidentally route work to the wrong state. → Mitigation: review/gate/mapping failures stay in `Workflow Review` and emit diagnostics.

## Migration Plan

1. Add `Workflow Review` to the required Linear team workflow states.
2. Update `elixir/WORKFLOW.md` and copied project workflow templates so completed work moves to `Workflow Review`, and `Todo` re-entry handles prReviewer feedback.
3. Update setup docs to list `Workflow Review` as a required non-standard state and describe the gate behavior.
4. Extend prReviewer with `full_pr`, expanded `pr-reviewer-state`, and a single fallback summary comment.
5. Update target repository automatic review workflow with `workflow_dispatch` inputs and a Linear gate step.
6. Configure required secrets for the target repository, including Linear API access.
7. Roll back by removing the gate step and restoring the workflow prompt to move completed work directly to `Human Review`; existing issues in `Workflow Review` would need manual movement to the desired state.

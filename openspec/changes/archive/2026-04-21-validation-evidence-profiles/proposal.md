## Why

Symphony's current workflow tells agents to reproduce, test, and run runtime validation, but it treats those expectations as mostly static instructions. That breaks down for mixed Linear work queues where labels such as `docs`, `bug`, `gameplay`, `visual`, or `ci` should require different validation depth.

This change introduces Linear-label-aware validation guidance so the agent can derive the appropriate verification ladder from issue labels, then record clear evidence or residual risk before handoff. Tickets with missing or non-standard labels fall back to the loosest validation rule.

## What Changes

- Add configurable validation levels such as compile, launch, reproduce, and changed-flow verification.
- Add configurable evidence types such as none, logs, screenshots, and videos.
- Add validation rules that match Linear issue labels to required validation levels and evidence types.
- Use the loosest default validation rule when labels are missing, malformed, or unmatched.
- Inject the resolved validation guidance into the agent prompt for each ticket.
- Update workflow instructions so workpad validation records required levels, evidence captured, unavailable levels, and residual risk.
- Preserve ticket-authored `Validation`, `Test Plan`, and `Testing` sections as required acceptance input that can only add to the resolved guidance.

## Capabilities

### New Capabilities

- `ticket-aware-validation-guidance`: Resolves per-ticket validation requirements from workflow configuration and Linear issue labels, then guides the agent to run the required validation levels and capture the required evidence types before handoff.

### Modified Capabilities

- None.

## Impact

- `elixir/WORKFLOW.md` front matter and prompt contract gain a validation guidance section.
- `SymphonyElixir.Config.Schema` gains validation configuration parsing and validation.
- `SymphonyElixir.Config` exposes normalized validation settings.
- `SymphonyElixir.PromptBuilder` injects resolved validation guidance into rendered prompts.
- Tests cover validation config defaults, invalid config, Linear label rule matching, loose fallback behavior, and prompt rendering.

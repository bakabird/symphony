## 1. Configuration Model

- [x] 1.1 Add validation embedded schemas to `SymphonyElixir.Config.Schema` for validation levels, evidence types, Linear label rules, and the loosest default rule.
- [x] 1.2 Validate supported unavailable behaviors and evidence types, then reject invalid validation configuration with clear config errors.
- [x] 1.3 Add normalized defaults so repositories without a `validation` block receive the loosest validation guidance.
- [x] 1.4 Expose validation settings through `SymphonyElixir.Config`.

## 2. Guidance Resolution

- [x] 2.1 Implement rule matching against Linear issue labels with normalized case-insensitive comparison.
- [x] 2.2 Preserve workflow rule order and select the first matching validation rule.
- [x] 2.3 Resolve the loosest default rule when Linear labels are missing, non-standard, or unmatched.
- [x] 2.4 Return a prompt-ready validation guidance map containing matched rule metadata, fully expanded validation levels, and separate evidence type requirements.

## 3. Prompt and Workflow Contract

- [x] 3.1 Inject resolved validation guidance into `SymphonyElixir.PromptBuilder` alongside `issue` and `attempt`.
- [x] 3.2 Update `elixir/WORKFLOW.md` front matter with validation levels and rules for the current repository.
- [x] 3.3 Update `elixir/WORKFLOW.md` prompt instructions to require validation activity by resolved level and evidence capture by evidence type.
- [x] 3.4 Update the workpad template validation section to record required levels, required evidence types, captured evidence, unavailable reasons, and residual risk.
- [x] 3.5 Preserve ticket-authored `Validation`, `Test Plan`, and `Testing` requirements as additive requirements in the prompt.

## 4. Tests and Documentation

- [x] 4.1 Add config parsing tests for validation defaults, configured levels, configured evidence types, configured rules, and invalid unavailable behavior.
- [x] 4.2 Add guidance resolution tests for Linear label matching, missing labels, non-standard labels, loose fallback behavior, and first-match rule order.
- [x] 4.3 Add prompt rendering tests proving validation guidance is available to Solid templates.
- [x] 4.4 Update `SPEC.md` with the validation guidance configuration and behavior contract.
- [x] 4.5 Run targeted tests plus `mix specs.check` for the completed change.

## Context

Symphony currently loads runtime configuration and the agent prompt from `WORKFLOW.md`, validates that configuration through `SymphonyElixir.Config.Schema`, and renders each agent turn through `SymphonyElixir.PromptBuilder`. The validation policy in the workflow prompt is mostly static: reproduce first, run targeted validation, execute ticket-authored validation sections, and run app-touching runtime validation where applicable.

The desired behavior is ticket-aware through Linear labels. A documentation change, a CI fix, a gameplay bug, and a visual regression should not all receive the same validation burden. The system needs a configuration-driven way to map Linear issue labels to validation levels, then specify which evidence types are required for those levels.

Validation levels and evidence types are separate concepts. Levels describe what activity must happen, such as `compile`, `launch`, `reproduce`, or `changed_flow`. Evidence types describe what artifact or signal must be recorded, such as `none`, `logs`, `screenshot`, or `video`.

## Goals / Non-Goals

**Goals:**

- Add a workflow configuration model for validation levels, evidence types, Linear label matching rules, and fallback behavior.
- Resolve validation guidance per ticket from Linear issue labels.
- Use the loosest validation rule when labels are missing, non-standard, or unmatched.
- Inject the resolved guidance into prompts so agents can plan and record validation consistently.
- Update workflow instructions and workpad shape to capture required validation levels, evidence, handoff reasons, and residual risk.
- Keep ticket-authored validation/test-plan sections mandatory and additive.

**Non-Goals:**

- Do not build an automated validation executor in this change.
- Do not parse workpad comments to enforce state transitions in the orchestrator yet.
- Do not add media upload, game capture, simulator control, or hardware-lab integrations.
- Do not change Linear state semantics or the existing Codex app-server execution path.

## Decisions

### Decision: Model validation levels separately from evidence types

Use configurable validation levels such as `compile`, `launch`, `reproduce`, and `changed_flow`. Use separate evidence types such as `none`, `logs`, `screenshot`, and `video`. A rule requires one or more levels and can specify the evidence types expected for each level.

This keeps the activity and the proof artifact distinct. For example, a `reproduce` level might require logs for a backend issue, screenshot for a UI issue, or video for a gameplay issue.

Alternative considered: model `logs`, `screenshot`, and `video` as validation levels. That mixes the action with its output and makes it harder to express "launch the game and capture logs" or "reproduce the bug and capture video".

### Decision: Match only Linear issue labels in the first implementation

Rules match normalized Linear labels from `issue.labels`. Matching should be case-insensitive and resilient to surrounding whitespace, but the system should not infer strict validation from title keywords, description text, project, or state in this change.

This makes behavior predictable and easy to explain: label policy controls validation policy. It also avoids surprising escalation based on unstructured text.

Alternative considered: match labels plus title and description keywords. That could catch under-labeled tickets, but it can also over-classify work and cause stricter validation than intended.

### Decision: Default to the loosest validation rule

Alternative considered: a single `evidence_profile` value such as `web_app` or `game`. That is useful as a default, but insufficient for a mixed queue where only some tickets require media or full runtime reproduction.

If a ticket has no labels, labels that do not match configured rules, or labels that are not part of the configured taxonomy, the resolver should use the loosest default rule. The default should require only the minimum project-safe validation, such as `compile` with evidence type `none` or a command result, depending on repository configuration.

This avoids punishing missing or messy labels with expensive reproduction/media requirements. Teams can make validation stricter by applying standard Linear labels.

Alternative considered: use a conservative strict fallback. That improves safety for under-labeled bugs, but it makes label hygiene problems expensive and contradicts the desired behavior.

### Decision: Resolve guidance before prompt rendering

`PromptBuilder` should render a `validation` object that already includes the matched rule and required levels for the current issue. The agent should not infer label policy from raw workflow configuration.

This makes behavior testable in Elixir and keeps prompt language focused on execution. The raw labels remain available in `issue.labels`, but the resolved guidance becomes the contract.

Alternative considered: inject all rules and ask the agent to choose. That increases ambiguity and makes prompt-only mistakes harder to test.

### Decision: Keep first enforcement prompt-driven

The first implementation should not block state transitions by reading and validating workpad evidence. Instead, the workflow prompt should require agents to record evidence and residual risk before handoff.

This fits the current architecture, where Symphony orchestrates turns and the agent updates the Linear workpad. Structured post-turn enforcement can be added later once workpad parsing or a generic progress-note model exists.

Alternative considered: enforce required evidence in the orchestrator immediately. That would require reliable structured extraction from comments and would risk false blocks before the evidence format is stable.

### Decision: Ticket-authored validation is additive

Any `Validation`, `Test Plan`, or `Testing` section in the ticket remains mandatory. The resolved ladder provides baseline guidance; ticket-authored requirements can add commands or evidence expectations but cannot reduce configured requirements.

This preserves the current workflow's acceptance discipline while allowing configuration to handle common cases.

## Risks / Trade-offs

- [Risk] Label-based matching can be incomplete or inconsistent across teams. -> Mitigation: use the loosest fallback for missing or unmatched labels and make stricter validation opt-in through standard Linear labels.
- [Risk] Prompt-driven enforcement can be ignored by a weak agent run. -> Mitigation: make validation guidance explicit in the prompt and workpad template now; add structured enforcement in a later change.
- [Risk] Required runtime/media levels may be unavailable in unattended environments. -> Mitigation: each level supports unavailable behavior such as `manual_handoff` or `blocked_with_reason`, and the workpad must record residual risk.
- [Risk] Overly strict rules may slow down low-risk tickets. -> Mitigation: rules can match low-risk labels like `docs` or `chore` to lighter levels.

## Migration Plan

1. Add validation configuration with defaults that produce the loosest rule for repositories that do not opt in.
2. Update `WORKFLOW.md` to include default levels and rules suitable for Symphony's current repository.
3. Inject resolved guidance into the prompt while keeping existing issue fields unchanged.
4. Update tests for config parsing, rule matching, and prompt rendering.

Rollback is straightforward: remove or ignore the `validation` workflow block and fall back to the existing static prompt text.

## Open Questions

- Should a later change support non-label match conditions, or should validation policy remain strictly label-driven?
- Should a later enforcement phase block `Human Review` transitions when required evidence is missing, or only mark the ticket as manual handoff?

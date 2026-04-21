## Context

`elixir/README.md` is the primary setup guide for Symphony. It currently marks copying the `commit`, `push`, `pull`, `land`, and `linear` skills as optional, even though the workflow assumes those repo-local skills are present for PR creation, review handling, and merge flow. The change is meant to remove that mismatch at the documentation boundary.

## Goals / Non-Goals

**Goals:**

- Make the README state that the repo-local skills are required setup prerequisites.
- Keep the `linear_graphql` dependency note adjacent to the required `linear` skill.
- Keep the change scoped to documentation so the runtime behavior stays unchanged.

**Non-Goals:**

- Do not add startup validation or any runtime enforcement for missing skills.
- Do not change the orchestration workflow, tracker behavior, or app-server code.
- Do not broaden the change into unrelated onboarding docs unless they create the same misleading prerequisite.

## Decisions

### Decision: Update only `elixir/README.md`

The misleading wording is localized to the setup section in `elixir/README.md`, so the smallest useful fix is to change that step in place.

Alternatives considered:

- Update `WORKFLOW.md` at the same time. Rejected because the user asked for the README prerequisite change and the workflow docs already depend on the skills in later sections.
- Add a separate install guide. Rejected because it would duplicate the same prerequisite and add maintenance cost.

### Decision: Keep the skill list explicit

The README SHOULD name `commit`, `push`, `pull`, `land`, and `linear` directly so users know exactly what must be copied.

Alternatives considered:

- Refer to a generic "skills bundle". Rejected because it hides the concrete prerequisites and makes omissions easier.
- Omit the individual names and rely on context. Rejected because the current problem is ambiguity in the setup path.

### Decision: Preserve the `linear_graphql` note next to the `linear` skill

The `linear` skill depends on Symphony's `linear_graphql` app-server tool, so the dependency note should remain in the same area as the required skill list.

Alternatives considered:

- Move the dependency note somewhere else. Rejected because the explanation is most useful immediately after the required skill list.

### Decision: No runtime enforcement changes

This change is about making the documentation honest and precise. It should not add new startup checks, skill installation logic, or workflow-state guards.

Alternatives considered:

- Fail startup when the skills are missing. Rejected as a separate product decision and a larger scope than the requested README change.

## Risks / Trade-offs

- [Risk] Users may still skim past the required step. -> Mitigation: use direct required language instead of optional wording.
- [Risk] Other docs may still imply the step is optional. -> Mitigation: search for nearby references and align only the ones that affect the same onboarding path.
- [Risk] Documentation alone does not guarantee the skills are present. -> Mitigation: treat runtime enforcement as a separate follow-up if needed later.

## Migration Plan

1. Update the README setup step to make the skill copy mandatory.
2. Review adjacent onboarding text for any lingering optional wording.
3. Confirm the final README reads as a required prerequisite chain.

## Open Questions

- Should any other onboarding docs mirror the same required wording, or is `elixir/README.md` the single source of truth?

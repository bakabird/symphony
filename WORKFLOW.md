---
tracker:
  kind: linear
  project_slug: "missioncenter-wip-1421e3d9187a"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    git clone --depth 1 --branch miision https://github.com/bakabird/symphony.git .
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    cd elixir && mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=xhigh --model gpt-5.4 app-server
  approval_policy: never
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
validation:
  levels:
    - name: compile
      description: "Run the narrowest compile/static/test command that proves changed code still works."
      command: "cd elixir && mise exec -- mix test"
      unavailable_behavior: blocked_with_reason
    - name: launch
      description: "Launch the affected service, UI, or runtime path when behavior depends on a running system."
      unavailable_behavior: manual_handoff
    - name: reproduce
      description: "Capture the pre-fix issue signal or explain why reproduction is impossible in this environment."
      unavailable_behavior: manual_handoff
    - name: changed_flow
      description: "Exercise the user-visible or operational flow changed by the patch."
      unavailable_behavior: manual_handoff
  evidence_types:
    - name: none
      description: "No external artifact required beyond a concise workpad result."
    - name: logs
      description: "Command output, log excerpt, or deterministic textual result."
    - name: screenshot
      description: "Screenshot proving the visual or UI state."
    - name: video
      description: "Short recording proving an interactive or temporal flow."
  default_rule:
    id: loosest
    description: "Loosest default for missing, non-standard, or unmatched Linear labels."
    levels:
      - name: compile
        evidence_type: none
  rules:
    - id: docs
      description: "Documentation-only work."
      labels: [docs, documentation, readme]
      levels:
        - name: compile
          evidence_type: none
    - id: ci
      description: "CI, build, or test infrastructure work."
      labels: [ci, build, test, tests]
      levels:
        - name: compile
          evidence_type: logs
    - id: bug
      description: "Bug fixes require reproduction plus changed-flow validation."
      labels: [bug, defect, regression]
      levels:
        - name: reproduce
          evidence_type: logs
        - name: compile
          evidence_type: logs
        - name: changed_flow
          evidence_type: logs
    - id: visual
      description: "Visual or UI changes require screenshot proof."
      labels: [visual, ui, frontend]
      levels:
        - name: compile
          evidence_type: logs
        - name: launch
          evidence_type: screenshot
        - name: changed_flow
          evidence_type: screenshot
    - id: gameplay
      description: "Interactive flows require runtime media proof."
      labels: [gameplay, game]
      levels:
        - name: reproduce
          evidence_type: video
        - name: compile
          evidence_type: logs
        - name: launch
          evidence_type: video
        - name: changed_flow
          evidence_type: video
---

You are working on a Linear ticket `{{ issue.identifier }}`.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required permissions, auth, or secrets.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Resolved validation guidance:
Matched rule: {{ validation.matched_rule.id }} ({% if validation.fallback %}default fallback: {{ validation.fallback_reason }}{% else %}matched labels: {{ validation.matched_rule.matched_labels }}{% endif %})

Required validation levels:
{% for level in validation.required_levels %}
- `{{ level.name }}`: {{ level.description }}
  - required evidence: `{{ level.evidence_type }}`
  - unavailable behavior: `{{ level.unavailable_behavior }}`
  {% if level.command %}
  - suggested command/activity: `{{ level.command }}`
  {% endif %}
{% endfor %}

Required evidence types:
{% for evidence in validation.required_evidence_types %}
- `{{ evidence.name }}` for levels {{ evidence.levels }}{% if evidence.description %}: {{ evidence.description }}{% endif %}
{% endfor %}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker, meaning missing required auth, permissions, or secrets. If blocked, record it in the workpad and move the issue according to workflow.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".
4. Work only in the provided repository copy. Do not touch any other path.
5. Use a single persistent `## Codex Workpad` comment for all progress, plan, and handoff notes.
6. Before implementation, capture a concrete reproduction signal and record it in the workpad `Notes` section.
7. Sync with `origin/mission` before edits, then record the pull result and resulting `HEAD` short SHA in the workpad.
8. Keep ticket metadata current, including state, checklist, acceptance criteria, and links.
9. If you find meaningful out-of-scope work, file a separate Linear issue instead of expanding scope.

## Prerequisite

The agent must be able to talk to Linear, either via a configured Linear MCP server or injected `linear_graphql` tool. If neither exists, stop and ask for Linear to be configured.

## Default posture

- Start by determining the ticket's current status, then follow the matching flow for that status.
- Reconcile the workpad before new edits.
- Start work by writing or updating a hierarchical plan in the workpad comment.
- Use the validation guidance above as non-negotiable acceptance input.
- If the ticket includes its own `Validation`, `Test Plan`, or `Testing` section, mirror it into the workpad and execute it in addition to the resolved validation levels.
- Keep the workpad as the single source of truth for progress and handoff notes.

## Status map

- `Backlog` -> out of scope for this workflow; do not modify.
- `Todo` -> move to `In Progress`, then bootstrap the workpad and begin execution.
- `In Progress` -> continue from the existing workpad.
- `Human Review` -> PR is attached and validated; wait for human approval.
- `Merging` -> approved by human; execute the `land` skill flow.
- `Rework` -> reviewer requested changes; plan, implement, and revalidate.
- `Done` -> terminal state; stop.

## PR requirements

- Target the GitHub PR at the `mission` base branch.
- Ensure the GitHub PR has the `symphony` label.
- Follow the repo PR template exactly.
- Use the `pull`, `push`, and `land` skills when they apply.

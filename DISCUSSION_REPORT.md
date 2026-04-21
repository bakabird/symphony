# Discussion Report: Agent Backends, Work Channels, and Validation Evidence

Date: 2026-04-20

## Context

This report summarizes an exploration of three related product and architecture questions:

1. Symphony should not be limited to Codex; it should also be able to run OpenCode and Claude Code.
2. The current system is deeply coupled to Linear; users should be able to connect different work or ticket channels.
3. The current validation expectations are difficult to apply quickly across game, hardware, mobile, desktop, and other app-heavy projects.

This is a discussion artifact only. It does not propose or implement code changes.

## Current Shape

The root `SPEC.md` already describes Symphony as a scheduler/runner with separate coordination,
execution, integration, and observability layers. The implementation, however, still centers on
Linear and Codex in several places:

- `elixir/lib/symphony_elixir/agent_runner.ex` directly starts `SymphonyElixir.Codex.AppServer`.
- Runtime state and observability names use `codex_*` fields throughout the orchestrator/dashboard.
- `elixir/lib/symphony_elixir/config/schema.ex` has a top-level `codex` config block rather than a generic agent backend block.
- `elixir/lib/symphony_elixir/tracker.ex` has a tracker boundary, but the normalized data model is still `SymphonyElixir.Linear.Issue`.
- `elixir/lib/symphony_elixir/codex/dynamic_tool.ex` exposes only `linear_graphql`.
- `elixir/WORKFLOW.md` hardcodes Linear-oriented behaviors: Linear MCP or `linear_graphql`, Linear state transitions, a single Linear workpad comment, and Linear follow-up issue creation.
- `SPEC.md` already calls out future work for first-class tracker write APIs and pluggable issue tracker adapters.

Conceptually, the current system looks like this:

```text
Linear issue
   |
   v
Tracker facade -> Orchestrator -> AgentRunner -> Codex.AppServer
   |                                      |
   |                                      `-> codex_* telemetry / app-server protocol
   `-> linear_graphql dynamic tool

WORKFLOW.md:
  Linear statuses
  Linear workpad comment
  Codex Workpad
  app-touching validation policy
```

This is functional for the first implementation, but it makes future support for OpenCode, Claude
Code, GitHub Issues, Jira, or non-ticket workflows look like exceptions rather than first-class
paths.

## Discussion Summary

### 1. Support Codex, OpenCode, and Claude Code

This should not be modeled as only a different command string.

Codex app-server, OpenCode, and Claude Code expose different automation surfaces:

- Codex currently fits the existing long-lived app-server shape: start session, start turn, stream events, serve dynamic tools, complete turn, continue thread.
- OpenCode has multiple usable surfaces: `opencode run --format json`, `opencode serve`, and `opencode acp`.
- Claude Code supports headless CLI usage with streamable JSON output, session resume, permission modes, and MCP/permission hooks. ACP adapters may provide a more protocol-like integration path.
- ACP itself is a JSON-RPC protocol over stdio for editor-agent interaction, with session and prompt lifecycle methods.

The more durable abstraction is an `AgentBackend` boundary:

```text
AgentBackend
  start_session(workspace, work_item, opts)
  run_turn(session, prompt, opts)
  cancel(session)
  stop_session(session)

Normalized events:
  session_started
  turn_started
  tool_requested
  permission_requested
  message_delta
  usage_updated
  turn_completed
  turn_failed
```

Possible backend families:

- `codex_app_server`: the existing backend, renamed and contained behind the generic interface.
- `acp_stdio`: likely the best shared target for OpenCode and future ACP-compatible agents.
- `claude_cli_stream`: a direct Claude Code fallback using non-interactive stream JSON.
- `opencode_http`: optional, useful if the service wants to manage or attach to `opencode serve`.

Important design pressure:

- Preserve multi-turn continuation semantics where possible.
- Normalize telemetry without pretending every backend has identical token, rate-limit, approval, or tool-call events.
- Keep backend-specific policy fields contained under backend config, rather than spreading `codex_*`, `claude_*`, and `opencode_*` names through orchestration state.

### 2. Decouple Linear into Modular Work Channels

The existing tracker adapter boundary is a useful starting point, but the real coupling is broader
than issue polling.

The workflow relies on:

- candidate work discovery,
- state refresh and reconciliation,
- semantic state transitions,
- a durable workpad/progress note,
- PR/artifact linking,
- comments and review feedback,
- follow-up work creation,
- raw Linear GraphQL as an agent tool.

A better model is to separate work discovery from work mutation and progress recording:

```text
                 +----------------------+
                 |      WorkChannel      |
                 | Linear/GitHub/Jira/...|
                 +----------+-----------+
                            |
                            v
+--------------+     +--------------+     +----------------+
| ProgressNote |<--->|   WorkItem    |--->|  Orchestrator   |
+--------------+     +--------------+     +-------+--------+
                                                   |
                                                   v
                                        +--------------------+
                                        |   AgentBackend      |
                                        | Codex/OpenCode/...  |
                                        +---------+----------+
                                                  |
                                        +---------v----------+
                                        | ToolBridge / MCP    |
                                        +--------------------+
```

Candidate interfaces:

```text
WorkSource:
  fetch_candidate_work()
  refresh_work_items(ids)
  fetch_terminal_work()

WorkSink:
  transition(work_id, semantic_state)
  upsert_progress_note(work_id, marker, body)
  link_artifact(work_id, url, kind)
  create_followup(parent_id, payload)

WorkChannelTools:
  expose generic tools to the agent
```

The key conceptual rename is from `Issue` to `WorkItem`, and from `Linear comment` or `Codex
Workpad` to `ProgressNote`.

For example:

- Linear maps `ProgressNote` to a comment.
- GitHub Issues maps it to an issue comment.
- Jira maps it to a comment or remote link.
- A local or hardware-oriented workflow might map it to a file, lab notebook, or run record.

The agent-facing tool surface should also become generic:

```text
work.get
work.progress.get
work.progress.update
work.transition
work.link_artifact
work.create_followup
work.comments.list
```

Raw provider tools such as `linear_graphql`, GitHub GraphQL, or Jira REST can remain as escape
hatches, but should not be the default portability layer.

### 3. Validation Needs Evidence Profiles

The current workflow has good intent:

- reproduce first,
- run targeted validation,
- execute ticket-provided validation requirements,
- for app-touching changes, run runtime validation and capture media.

The weak point is that it assumes a validation environment that is easy to launch and instrument.
That is not true for many project types:

- game projects may require a scene, seed, replay, GPU path, or capture rig;
- hardware projects may require physical devices, firmware flashing, lab equipment, or HIL rigs;
- mobile projects may need simulators, device accounts, provisioning profiles, or manual device QA;
- desktop apps may require OS-specific launch permissions and visual confirmation;
- embedded or backend-adjacent systems may have no meaningful "launch app" equivalent.

The recommended abstraction is not "always run this command"; it is a validation evidence contract:

```text
ValidationEvidence
  reproduction_signal
    before-change behavior is observed or credibly constrained

  targeted_proof
    changed behavior is directly tested

  runtime_smoke
    integrated app/device/game path is exercised when the environment supports it
```

Each evidence class can have a status:

```text
required
best_effort
manual_handoff
not_applicable
blocked_with_reason
```

Example project profiles:

| Project Type | Reproduction Signal | Targeted Proof | Runtime/App Evidence |
| --- | --- | --- | --- |
| CLI/library | failing test or command output | unit/integration test | usually not applicable |
| Web app | screenshot, Playwright failure, console/log signal | targeted route/component test | browser launch with screenshot/video |
| Mobile app | simulator repro, build log, screenshot | unit/UI test | simulator/device run or manual handoff |
| Game | deterministic replay, seed, scene capture | gameplay/system test or golden frame/log | smoke scene, frame capture, FPS/log |
| Hardware/firmware | device log, bench reading, failing HIL case | HAL mock, firmware test, compile | HIL/manual bench checklist |
| Desktop app | launch log, repro script, screenshot | targeted component/integration test | app launch and changed-flow check |

The important rule is honesty: if full runtime validation cannot be done in-session, the agent should
record the gap and residual risk instead of pretending validation happened.

Example evidence summary:

```text
Evidence:
  reproduction: user-provided video plus local log excerpt; physical device unavailable
  targeted: unit test X passed
  runtime: manual_handoff; requires iOS device with account Y
  residual risk: native navigation path was not exercised locally
```

## Suggested Change Decomposition

These can be separate design changes rather than one large refactor.

### A. Generalized Agent Backends

Goal:

- Move `Codex.AppServer` behind a generic agent backend interface.
- Normalize agent events and session lifecycle.
- Preserve the existing Codex path as the first backend.
- Add an ACP-oriented backend shape for OpenCode and future compatible agents.

Likely first artifacts:

- backend behaviour definition,
- normalized event schema,
- config migration from `codex` to `agent_backend` or `executor`,
- compatibility behavior for existing `codex` config.

### B. Modular Work Channels

Goal:

- Rename orchestration domain concepts from Linear-specific `Issue` naming toward generic `WorkItem`.
- Split polling, mutation, and progress-note responsibilities.
- Make Linear one work channel implementation rather than the default mental model.
- Replace `linear_graphql` as the primary workflow primitive with generic work tools.

Likely first artifacts:

- `WorkItem` normalized model,
- `WorkSource` and `WorkSink` contracts,
- `ProgressNote` contract,
- semantic state mapping,
- Linear adapter mapped into the new contracts.

### C. Validation Evidence Profiles

Goal:

- Replace one-size-fits-all validation commands with configurable evidence profiles.
- Keep reproduction and targeted proof as first-class expectations.
- Allow runtime validation to be required, best-effort, manual-handoff, not applicable, or blocked with reason.
- Make validation reporting portable across web, app, game, hardware, firmware, and library projects.

Likely first artifacts:

- validation evidence schema,
- project profile examples,
- workflow prompt language updates,
- handoff/reporting requirements for unverified runtime paths.

## Open Questions

- Should ACP be the primary non-Codex integration path, or should OpenCode and Claude Code each get direct first-party backends first?
- How much of ticket mutation should the orchestrator own versus exposing tools to the agent?
- Should generic work tools be injected dynamically by Symphony, implemented as MCP servers, or both?
- What is the minimum common `WorkItem` schema that can support Linear, GitHub Issues, Jira, and local workflows without becoming too vague?
- Should validation profiles live in `WORKFLOW.md`, a separate file, or generated project metadata?
- How strict should Symphony be when required evidence is missing: block state transition, mark manual handoff, or allow configurable policy?

## Recommended Near-Term Direction

The most stable sequence appears to be:

1. Define the generic concepts in the spec: `AgentBackend`, `WorkItem`, `ProgressNote`, and `ValidationEvidence`.
2. Preserve current Codex and Linear behavior while moving names and boundaries toward the generic contracts.
3. Add an ACP backend as the first non-Codex execution path.
4. Introduce validation profiles in workflow policy before trying to automate every project type.

This keeps existing behavior usable while reducing the two largest sources of lock-in: Codex-specific
execution assumptions and Linear-specific collaboration assumptions.

## References

- `SPEC.md`
- `elixir/WORKFLOW.md`
- `elixir/lib/symphony_elixir/agent_runner.ex`
- `elixir/lib/symphony_elixir/codex/app_server.ex`
- `elixir/lib/symphony_elixir/codex/dynamic_tool.ex`
- `elixir/lib/symphony_elixir/tracker.ex`
- `elixir/lib/symphony_elixir/config/schema.ex`
- OpenCode CLI: https://opencode.ai/docs/cli/
- OpenCode server: https://opencode.ai/docs/server/
- OpenCode ACP: https://opencode.ai/docs/acp/
- Claude Code CLI: https://code.claude.com/docs/en/cli-usage
- Agent Client Protocol overview: https://agentclientprotocol.com/protocol/overview
- Agent Client Protocol transports: https://agentclientprotocol.com/protocol/transports

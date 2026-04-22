# Discussion Report: Agent Backends, Work Channels, and Validation Evidence

Date: 2026-04-20

## Context

This report summarizes an exploration of three related product and architecture questions:

1. Symphony should not be limited to Codex; it should also be able to run OpenCode and Claude Code.
2. The current system is deeply coupled to Linear; users should be able to connect different work or ticket channels.
3. The current validation expectations are difficult to apply quickly across game, hardware, mobile, desktop, and other app-heavy projects.

This is a discussion artifact only. It does not propose or implement code changes.

## 已执行

### 1) 现状盘点（Current Shape）

已完成对当前实现和架构差距的梳理，结论是系统虽有分层设计，但实现仍偏向 Codex + Linear：

- `elixir/lib/symphony_elixir/agent_runner.ex` 直接启动 `SymphonyElixir.Codex.AppServer`。
- 运行态与可观测命名大量使用 `codex_*`。
- `elixir/lib/symphony_elixir/config/schema.ex` 仍是顶层 `codex` 配置块。
- `elixir/lib/symphony_elixir/tracker.ex` 的标准模型仍是 `SymphonyElixir.Linear.Issue`。
- `elixir/lib/symphony_elixir/codex/dynamic_tool.ex` 仅暴露 `linear_graphql`。
- `elixir/WORKFLOW.md` 仍硬编码 Linear 状态流与工作记录路径。

当前概念链路（已确认）：

```text
Linear issue
   |
   v
Tracker facade -> Orchestrator -> AgentRunner -> Codex.AppServer
   |                                      |
   |                                      `-> codex_* telemetry / app-server protocol
   `-> linear_graphql dynamic tool
```

### 2) 核心方案讨论产出（Discussion Summary）

#### A. Agent 后端泛化（Codex/OpenCode/Claude Code）

已形成统一抽象方向：用 `AgentBackend` 边界而不是仅替换命令字符串。

```text
AgentBackend
  start_session(workspace, work_item, opts)
  run_turn(session, prompt, opts)
  cancel(session)
  stop_session(session)
```

已识别候选后端族：

- `codex_app_server`
- `acp_stdio`
- `claude_cli_stream`
- `opencode_http`（可选）

#### B. Work Channel 模块化（去 Linear 强耦合）

已形成方向：从 `Issue` 过渡到 `WorkItem`，从单一评论语义过渡到 `ProgressNote`，并拆分读取与写入职责。

候选接口已明确：

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
```

#### C. 验证策略升级（Validation Evidence Profiles）

已形成方向：从“一刀切命令”升级为“证据契约”。

```text
ValidationEvidence
  reproduction_signal
  targeted_proof
  runtime_smoke
```

证据状态枚举已讨论完成：

```text
required
best_effort
manual_handoff
not_applicable
blocked_with_reason
```

### 3) 已形成的分解和落地顺序

已完成变更拆分建议（A/B/C）与近期开工顺序建议：

1. 在规范层定义 `AgentBackend`、`WorkItem`、`ProgressNote`、`ValidationEvidence`。
2. 在保持现有行为可用前提下，逐步将命名与边界迁移到通用契约。
3. 增加 ACP 作为首个非 Codex 后端路径。
4. 在工作流策略引入验证证据 profile，再逐步扩展自动化覆盖。

### 4) 参考资料已收集

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

## 待执行

### 1) 规范与配置落地

- 在 `SPEC.md` 引入并固定 `AgentBackend`、`WorkItem`、`ProgressNote`、`ValidationEvidence` 的正式定义。
- 将配置从 `codex` 迁移到通用 `agent_backend`（或 `executor`）模型，并保留兼容行为。

### 2) AgentBackend 工程化改造

- 抽象 backend behaviour 与统一事件 schema。
- 将现有 `Codex.AppServer` 封装为 `codex_app_server` 实现。
- 增加 `acp_stdio` 首个跨代理后端实现。

### 3) Work Channel 工程化改造

- 引入 `WorkItem` 标准模型，替换线性 `Issue` 心智模型。
- 落地 `WorkSource` / `WorkSink` / `ProgressNote` 契约。
- 将 Linear 适配到新契约，并提供通用 `work.*` 工具作为默认 agent 工具面。

### 4) Validation Evidence 工程化改造

- 定义验证证据 schema 与项目类型 profile。
- 更新 workflow prompt 与报告模板，要求在无法做运行态验证时明确 handoff 与残余风险。

### 5) 待决策问题（Open Questions）

- ACP 是否作为非 Codex 集成主路径，还是先做 OpenCode/Claude 各自直连？
- work item 的变更职责应更多在 orchestrator 还是 agent tools？
- 通用 work tools 应由 Symphony 动态注入、MCP 提供，还是两者并存？
- 兼容 Linear/GitHub/Jira/本地流程的最小 `WorkItem` 公共模型如何定义？
- validation profile 放在 `WORKFLOW.md`、独立文件，还是项目元数据生成？
- 必需证据缺失时，默认策略是阻断状态流转、标记 handoff，还是可配置？

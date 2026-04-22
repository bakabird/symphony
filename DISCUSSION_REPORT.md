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

已形成后端路径决策：

- ACP 是支持 ACP 的 agent 的首选标准后端路径，但不是所有非 Codex 集成的唯一主路径。
- OpenCode ACP 作为首个非 Codex 后端实现，目标命令为 `opencode acp`，由 `acp_stdio` 适配。
- Claude Code 先通过专用 `claude_cli_stream` 后端接入，使用 CLI stream/json 输出与会话续接能力；除非后续出现稳定可用的 Claude Code ACP-compatible server，否则不阻塞在 ACP 上。
- Symphony 的核心边界仍应是 `AgentBackend`，而不是把实现绑定为 `ACPBackend`。

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

已形成 agent-facing work 操作面的最终决策：通用 work tools 不以 MCP server 或 backend-specific dynamic tool injection 作为主路径，而是采用各渠道 skills + provider-neutral CLI/scripts 作为唯一 canonical surface。

```text
Codex / OpenCode / Claude Code
   |
   v
channel-specific work skill
   |
   v
`symphony-work` CLI / scripts
   |
   v
Symphony Work Facade
   |
   v
WorkSource / WorkSink adapters
   |
   v
Linear / GitHub / Jira / local workflows
```

该方向的核心边界：

- skills 负责告诉模型何时、如何调用稳定命令；模型负责理解流程、判断时机、组织上下文。
- `symphony-work` CLI/scripts 负责执行语义化操作，并强制校验 run scope、current work item binding、幂等 upsert、provider authorization、状态映射与 audit。
- 各渠道 skills 只做薄包装，例如 `.codex/skills/work/SKILL.md`、`.claude/skills/work/SKILL.md`、`.opencode/skills/work/SKILL.md` 或 `.agents/skills/work/SKILL.md`，不复制 provider 业务逻辑。
- MCP、Codex dynamic tools、provider-native MCP 或 raw provider API 只作为兼容、调试或 escape hatch；不作为 Work Channel conformance 的必需条件。
- `linear_graphql` 可保留为迁移期和低层调试能力，但长期默认 workflow 不应依赖 agent 直接理解 Linear GraphQL。

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
3. 将现有 `Codex.AppServer` 包装为 `codex_app_server`，作为兼容基线。
4. 增加 `acp_stdio`，并以 OpenCode ACP 作为首个非 Codex 后端路径。
5. 增加 `claude_cli_stream`，通过 Claude Code CLI stream/json 输出接入。
6. 在工作流策略引入验证证据 profile，再逐步扩展自动化覆盖。

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
- OpenCode skills: https://opencode.ai/docs/skills
- Claude Code CLI: https://code.claude.com/docs/en/cli-usage
- Claude Code skills: https://code.claude.com/docs/en/skills
- Agent Client Protocol overview: https://agentclientprotocol.com/protocol/overview
- Agent Client Protocol transports: https://agentclientprotocol.com/protocol/transports

## 当前项目完成情况核对（2026-04-22）

### 已完成

#### Validation Evidence / Ticket-aware Validation Guidance

验证策略升级已经从讨论落地为 `ticket-aware-validation-guidance` 能力：

- OpenSpec change `validation-evidence-profiles` 已归档，任务清单全部完成。
- `openspec/specs/ticket-aware-validation-guidance/spec.md` 已存在正式需求，覆盖 validation levels、evidence types、Linear label 匹配、fallback、prompt rendering、workpad evidence 记录、ticket-authored validation additive。
- `SPEC.md` 已加入 `validation` 配置模型和 prompt contract。
- `elixir/WORKFLOW.md` 已加入 `validation` front matter，并在 prompt 中渲染 resolved validation guidance。
- `SymphonyElixir.Config.Schema` 已实现 validation levels、evidence types、rules、default rule 的 schema、默认值和校验。
- `SymphonyElixir.ValidationGuidance` 已实现基于 issue labels 的解析逻辑。
- `SymphonyElixir.PromptBuilder` 已将 resolved validation guidance 注入模板上下文。
- 测试文件 `elixir/test/symphony_elixir/validation_guidance_test.exs` 已覆盖默认值、配置解析、label 匹配、fallback、first-match rule order 和 prompt rendering。

对应原待执行项状态：

- “定义验证证据 schema 与项目类型 profile”：已完成核心落地，当前形态是 `WORKFLOW.md` 驱动的 validation levels + evidence types + label rules。
- “更新 workflow prompt 与报告模板，要求在无法做运行态验证时明确 handoff 与残余风险”：已完成 prompt/workpad 层落地。

### 部分完成

#### 规范与配置落地

`ValidationEvidence` 方向已经在规范、配置、workflow 和 prompt 中落地，但 `AgentBackend`、`WorkItem`、`ProgressNote` 仍未成为正式规范或实现边界。

已完成部分：

- `SPEC.md` 已记录 validation guidance 配置和 prompt 行为。
- `WORKFLOW.md` 已作为 validation profile 的第一落点。
- 必需 runtime/media evidence 不可用时，已有 `manual_handoff` / `blocked_with_reason` 表达和 workpad 记录要求。

仍未完成部分：

- `SPEC.md` 尚未正式定义 `AgentBackend`、`WorkItem`、`ProgressNote`。
- 顶层配置仍是 `codex` block，尚未迁移到 `agent_backend` / `executor` 模型。
- 必需证据缺失时还没有 orchestrator 级强制门禁；当前是 prompt/workpad 驱动。

### 未完成

#### AgentBackend 工程化改造

当前项目仍直接运行 `SymphonyElixir.Codex.AppServer`：

- `AgentRunner` 仍直接 alias/call `SymphonyElixir.Codex.AppServer`。
- 运行事件和可观测语义仍大量使用 `codex_*`。
- 尚无 `AgentBackend` behaviour。
- 尚无 `codex_app_server` backend wrapper。
- 尚无 `acp_stdio` 实现。
- 尚无 `opencode acp` 集成验证。
- 尚无 `claude_cli_stream` 实现。

#### Work Channel 工程化改造

当前项目仍以 Linear issue 为主模型：

- `SymphonyElixir.Linear.Issue` 仍是标准 work record。
- `Tracker` facade 仍以 issue/tracker API 命名。
- `Codex.DynamicTool` 仍只暴露 `linear_graphql`。
- 尚无 `WorkItem` 标准模型。
- 尚无 `WorkSource` / `WorkSink` / `ProgressNote` 契约。
- 尚无通用 `work.*` agent 工具面。

### 验证说明

本次核对尝试运行：

- `mise exec -- mix test test/symphony_elixir/validation_guidance_test.exs`
- `mise exec -- mix specs.check`

但本地 `elixir/mise.toml` 未被 trust，命令在执行前被 `mise` 阻断；未自动执行 `mise trust`，因此没有改变本机信任状态。

## 剩余待执行

### 1) 规范与配置落地

- 在 `SPEC.md` 引入并固定 `AgentBackend`、`WorkItem`、`ProgressNote` 的正式定义。
- 将配置从 `codex` 迁移到通用 `agent_backend`（或 `executor`）模型，并保留兼容行为。
- 补齐当前 OpenSpec `ticket-aware-validation-guidance` 的 `Purpose`，避免归档后仍保留 TBD。

### 2) AgentBackend 工程化改造

- 抽象 backend behaviour 与统一事件 schema。
- 将现有 `Codex.AppServer` 封装为 `codex_app_server` 实现。
- 增加 `acp_stdio` 首个跨代理后端实现，优先验证 `opencode acp`。
- 增加 `claude_cli_stream` 专用后端，优先使用 Claude Code CLI 的 stream/json 输出、session resume、permission mode 与 MCP 配置能力。

### 3) Work Channel 工程化改造

- 引入 `WorkItem` 标准模型，替换线性 `Issue` 心智模型。
- 落地 `WorkSource` / `WorkSink` / `ProgressNote` 契约。
- 将 Linear 适配到新契约，并通过 repo-local skills + `symphony-work` CLI/scripts 提供通用 work 操作面。

### 4) Validation Evidence 工程化改造

- 后续可选：增加 orchestrator 级 evidence enforcement，决定是否在缺失必需证据时阻断状态流转。
- 后续可选：将 `WORKFLOW.md` 中的 validation rules 抽象为更通用的项目类型 profile 或项目元数据生成机制。

### 5) 待决策问题（Open Questions）

- work item 的变更职责应更多在 orchestrator 还是 agent tools？
- 兼容 Linear/GitHub/Jira/本地流程的最小 `WorkItem` 公共模型如何定义？
- validation profile 是否长期保留在 `WORKFLOW.md`，还是后续升级为独立文件/项目元数据生成？
- 必需证据缺失时，是否需要从 prompt/workpad 记录升级为 orchestrator 强制门禁？

### 6) 已决策问题（Decisions）

- ACP 作为支持 ACP 的 agent 的首选标准后端路径。
- OpenCode ACP 是首个非 Codex 后端目标，通过 `acp_stdio` 集成。
- 非 Codex 支持不被 ACP 可用性阻塞；Claude Code 先通过 `claude_cli_stream` 专用后端集成。
- `AgentBackend` 是 Symphony 的长期抽象边界，ACP、Codex app-server、Claude CLI stream 都只是该边界下的具体实现族。
- 通用 work 操作面的最终唯一形态是各渠道 skills + provider-neutral `symphony-work` CLI/scripts；不要求 MCP server 或 backend dynamic tool injection。
- MCP、Codex dynamic tools、provider-native MCP 与 raw provider API 仅作为兼容、调试或 escape hatch，不是 Work Channel 的 canonical interface。
- 模型被信任通过 skill 自主选择调用 CLI/scripts；CLI/scripts 必须负责 run scope、current work item binding、幂等性、provider authorization、状态映射与 audit。
- validation guidance 第一阶段落点是 `WORKFLOW.md` front matter + prompt contract。
- validation evidence 第一阶段采用 prompt/workpad 驱动记录，不做 orchestrator 强制阻断。
- ticket-authored `Validation` / `Test Plan` / `Testing` 要求是 additive，不能被配置生成的 validation guidance 降级。

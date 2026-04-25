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

## 当前项目完成情况核对（2026-04-25）

### 已实现

#### 1) AgentBackend 兼容层已落地

`AgentBackend` 这一层已经不再停留在讨论阶段，当前代码已完成首轮工程化改造：

- OpenSpec change `agent-backend-compatibility-layer` 的任务清单已全部勾选完成。
- `elixir/lib/symphony_elixir/agent_backend.ex` 已定义 `AgentBackend` behaviour，以及 backend/session/turn/event 的共享约定与 runtime event normalization helper。
- `elixir/lib/symphony_elixir/agent_backend/resolver.ex` 已提供 backend resolver，默认返回 `SymphonyElixir.AgentBackend.CodexAppServer`。
- `elixir/lib/symphony_elixir/agent_backend/codex_app_server.ex` 已将现有 `SymphonyElixir.Codex.AppServer` 包装为默认 `codex_app_server` backend。
- `elixir/lib/symphony_elixir/agent_runner.ex` 已通过 resolved backend 执行 session/turn，不再直接调用 `SymphonyElixir.Codex.AppServer`；同时已构造 backend context、turn map 和最小 `work_item` map。
- continuation prompt 已从 “previous Codex turn” 调整为 “previous agent turn”。
- `elixir/lib/symphony_elixir/orchestrator.ex` 已接收 `:agent_worker_update`，并保留 `:codex_worker_update` 兼容路径。
- `SPEC.md` 已加入 AgentBackend runtime contract，并明确默认兼容路径是 `codex_app_server`；OpenCode/ACP/Claude CLI stream 被标记为后续实现。
- 现有观测面仍保留 `codex_*` 字段，以兼容 dashboard、snapshot 和 presenter。

#### 2) Validation Evidence / Ticket-aware Validation Guidance 已落地

验证策略升级已经从讨论落地为正式能力：

- OpenSpec change `validation-evidence-profiles` 已归档，任务清单全部完成。
- `openspec/specs/ticket-aware-validation-guidance/spec.md` 已存在正式需求，覆盖 validation levels、evidence types、Linear label 匹配、fallback、prompt rendering、workpad evidence 记录、ticket-authored validation additive。
- `SPEC.md` 已加入 `validation` 配置模型和 prompt contract。
- `elixir/WORKFLOW.md` 已加入 `validation` front matter，并在 prompt 中渲染 resolved validation guidance。
- `SymphonyElixir.Config.Schema` 已实现 validation levels、evidence types、rules、default rule 的 schema、默认值和校验。
- `SymphonyElixir.ValidationGuidance` 已实现基于 issue labels 的解析逻辑。
- `SymphonyElixir.PromptBuilder` 已将 resolved validation guidance 注入模板上下文。
- `elixir/test/symphony_elixir/validation_guidance_test.exs` 已覆盖默认值、配置解析、label 匹配、fallback、first-match rule order 和 prompt rendering。

对应原待执行项状态：

- “定义验证证据 schema 与项目类型 profile”：已完成当前版本落地，当前形态是 `WORKFLOW.md` 驱动的 validation levels + evidence types + label rules。
- “更新 workflow prompt 与报告模板，要求在无法做运行态验证时明确 handoff 与残余风险”：已完成 prompt/workpad 层落地。

#### 3) Repo-local skills 前置要求已落地

与后续 Work Channel 方向相关的 repo-local skills 前置要求也已进入实现：

- `openspec/specs/repo-local-skills-required/spec.md` 已定义 `commit`、`push`、`pull`、`land`、`linear` 为必需 repo-local skills。
- `elixir/README.md` 已将这些 skills 标为 required prerequisites，而不是 optional setup。
- `elixir/README.md` 已显式说明 `linear` skill 依赖 Symphony 的 `linear_graphql` app-server tool。

### 部分实现

#### 1) Tracker/Work 抽象有初步边界，但还不是通用 Work Channel

目前已有一些基础抽象，但距离讨论中的 Work Channel 设计还差很远：

- `elixir/lib/symphony_elixir/tracker.ex` 已经是 adapter boundary，而不是把所有 Linear 逻辑都散落在业务代码中。
- `Tracker.adapter/0` 当前可以在运行时选择 `memory` 或 `linear` 适配器。
- `AgentRunner` 和 `AgentBackend` 已经传递最小 `work_item` map，这说明运行时边界开始弱化对完整 Linear struct 的依赖。

但这些仍不足以算作 Work Channel 泛化完成：

- 上层语义仍是 `issue` / `tracker`，不是 `WorkItem` / `WorkSource` / `WorkSink`。
- `memory` 更像测试/本地适配器，不是 GitHub/Jira/local workflows 的正式通道实现。

### 未实现

#### 1) 非 Codex backend 仍未落地

虽然 `AgentBackend` compatibility layer 已完成，但真正的多 agent backend 目标还没有实现：

- 尚无 `acp_stdio` backend。
- 尚无 `opencode acp` 集成验证。
- 尚无 `claude_cli_stream` backend。
- backend 选择目前主要通过运行时 opts / 测试 override 完成，尚未形成 operator-facing 的正式配置入口。
- `WORKFLOW.md` 与 `Config.Schema` 顶层仍是 `codex` 配置块，尚未迁移到通用 `agent_backend` / `executor` 模型。
- 运行态和可观测字段仍大量保留 `codex_*` 命名；这是兼容性选择，不是最终中性命名。

#### 2) Work Channel 泛化仍基本未开始

当前项目仍以 Linear issue 为主模型：

- `SymphonyElixir.Linear.Issue` 仍是主要 work record。
- `Tracker` facade 仍以 issue/tracker API 命名。
- `SymphonyElixir.Codex.DynamicTool` 仍只暴露 `linear_graphql`。
- `SPEC.md` 仍未定义正式 `WorkItem`、`ProgressNote`、`WorkSource`、`WorkSink` 契约。
- 尚无 repo-local `symphony-work` CLI/scripts。
- 尚无 provider-neutral `work.*` agent 操作面。
- 运行时支持仍主要围绕 `tracker.kind == linear` 展开；`memory` 适配器存在，但不代表 GitHub/Jira/local workflow 已接入。

#### 3) 文档与规格清理仍有尾项

- `openspec/specs/ticket-aware-validation-guidance/spec.md` 的 `Purpose` 仍是 `TBD`。
- `openspec/specs/repo-local-skills-required/spec.md` 的 `Purpose` 仍是 `TBD`。
- `agent-backend-compatibility-layer` 的代码和任务已完成，但当前仍保留在活跃 change 目录，尚未完成归档整理。

### 验证说明

本次核对已实际运行最小验证，而不是仅做静态阅读：

- `mise exec -- mix test test/symphony_elixir/agent_backend_test.exs`
  - 结果：`3 tests, 0 failures`
- `mise exec -- mix test test/symphony_elixir/agent_backend/codex_app_server_test.exs test/symphony_elixir/agent_runner_test.exs test/symphony_elixir/validation_guidance_test.exs test/symphony_elixir/orchestrator_status_test.exs`
  - 结果：`56 tests, 0 failures`

本次未执行 `mise trust`，也没有修改本机信任状态；测试是通过 `mise exec -- ...` 直接完成的。

## 剩余待执行

### 1) 完成真正的多 backend 支持

- 增加 `acp_stdio`，优先验证 `opencode acp`。
- 增加 `claude_cli_stream`，接入 Claude Code CLI stream/json 输出与 session resume 能力。
- 将 backend 选择从测试 override 升级为正式 workflow/config 能力。
- 逐步把 `codex_*` 观测兼容字段迁移到真正的 backend-neutral 语义。

### 2) 完成 Work Channel 泛化

- 引入正式 `WorkItem` 标准模型，替换以 `Issue` 为中心的心智模型。
- 落地 `WorkSource` / `WorkSink` / `ProgressNote` 契约。
- 将 Linear 适配到新契约。
- 通过 repo-local skills + `symphony-work` CLI/scripts 提供通用 work 操作面。
- 在此基础上再考虑 GitHub、Jira、local workflows 等新 channel。

### 3) 补齐文档和 OpenSpec 收尾

- 为已归档 spec 补齐 `Purpose`，清掉 `TBD`。
- 归档已完成的 `agent-backend-compatibility-layer` change。
- 在 `SPEC.md` 中继续把“已兼容保留的 Codex 细节”与“长期中性契约”拆得更清楚。

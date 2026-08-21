# PMind 项目探索与上下文快照

> 文档用途：在模型上下文压缩、人员交接或会话中断后，恢复 PMind 当前阶段的完整探索结论。
>
> 状态：Validation Sprint 第 0 阶段已归档，第 1 阶段校准准备中；尚未进入 Agent 运行时实现。
>
> 快照日期：2026-08-21（Asia/Shanghai）。价格、产品能力、仓库状态和第三方 Skill 内容均可能在此日期后变化，实施前应重新核验。

## 0. 压缩后恢复须知

如果后续模型只保留了有限上下文，应先完整阅读本文，再继续 PMind 工作。不得把本文中的“建议”“候选”“待授权事项”误认为已经实施。

当前事实：

- PMind 仓库已完成 Git 初始化，默认分支为 `main`。
- 公开 GitHub 仓库为 `https://github.com/zhenkun26/PMind`，本地 `origin` 已指向该地址；Git 历史从本次公开引导归档开始。
- 本文最初是仓库的第一份项目文档，现已补充治理、领域、Reference、Eval 和 Skill 文件。
- 已从 `mattpocock/skills` 精选并本地化 12 个仓库级 Skill，固定上游 commit 为 `0ab1b63a410a03d3627979a109c8695de27af954`；详情见 `reference/github/mattpocock__skills/`。
- 已创建 Prompt Package、Clarification、Review Lenses、Concierge Runbook、Eval Schema、Rubric 和 10 个尚未运行的合成种子案例；阶段决策见 `reference/research/next-execution-stage-2026-08-21.md`。
- 已创建首批 3 案例校准 Wave、无依赖验证器、3 个合成 Fixture、仓库外隔离工作区准备器、Executor Profile 契约和统一 preflight；Fixture 已冻结 workspace digest 并通过基础自检，但由于四个角色未分配、Profile 仍有六项未决字段且本次 Wave 的运行副本未就绪，Wave 保持 `blocked`。
- 已将 Case Schema 升级到 `0.2.0`，补齐模型、Profile、Workspace Set、工作区结果 revision、返工与分段耗时溯源；新增 Acceptance Result Schema `0.1.0` 和 `consensus` / `needs_adjudication` / `adjudicated` 三态验证。10 个种子案例完成无数据迁移，当前仍为 0 条运行、0 条验收结果。
- 已将 Prompt Package v0 落成 `schemas/prompt-package-v0.yaml`、依赖无关的只读校验 CLI 和合成测试夹具；稳定 ID、引用、六个 Review Lenses、Approval Point 状态与 Handoff 授权边界现在可机器校验。测试夹具不是实际 Package 或效果证据。
- 已将 Clarification Session v0 落成 `schemas/clarification-session-v0.yaml`、依赖无关的只读校验 CLI 和合成测试夹具；不可变 Intake、九维 gap、问题优先级、连续轮次、Compile Gate 与 Session → Package lineage 现在可机器校验。校验器不会代替用户回答或自动生成 Package。
- 尚未运行基线/PMind 对照案例；空 `run_records` 不代表通过验证。
- 尚未确定最终技术栈、托管模式、首个下游执行平台和商业版本边界。
- 用户已授权本地工作流引导，以及本次创建公开仓库、归档提交和推送。未来的提交、推送、Issue、Release、部署和产品依赖安装仍需按任务单独授权。

恢复工作时应遵循的原则：

1. 先核验仓库和外部资料的最新状态。
2. 保留用户已有变更，不覆盖、不删除、不擅自提交。
3. 第三方 Skill 采用精选、固定版本、审查后本地化的方式，不整包无差别安装。
4. 任何 GitHub Issue、远程提交、推送、部署、标签修改等外部写操作，都需要明确授权。
5. Skill 中的流程建议不能替代系统、开发者、仓库级规则，也不能承担不可绕过的安全控制。

## 1. 原始项目设想

项目名称：**PMind**。

初始方向是一个与产品经理工作相关的 `Skill + Agent` 项目，但最终形态仍需通过探索决定。用户输入一个初始需求或提示词后，PMind 通过多轮询问、GitHub 项目检索、Skill 检索、框架检索和多角度审查，帮助用户补齐上下文、优化需求表达，并将优化结果交给后续 Agent、研发团队或其他执行系统。

内部生产过程中可以建立 `reference/`，在用户允许的范围内保存研究过的 GitHub 项目、Skill、Agent、框架和行业资料，并记录来源、版本、许可证、安全审查和实际借鉴内容。

项目探索不应只局限于“根据参考项目进行改造”，还可以同时采用：

- 基于已有开源项目、Skill 和框架的可验证复用；
- 基于行业先进标准的组合和 PMind 自研创新；
- 基于模型已有知识形成候选方案，再以外部资料和评测验证；
- 围绕商业化趋势、难点、成本、周期、用户画像和产品经理完整工作链路持续迭代。

## 2. 产品定位结论

### 2.1 不应只做“提示词润色器”

单纯改写措辞容易同质化，也很难形成企业级价值。更合适的定位是：

> **PMind 是一个从模糊意图到可执行规格的编译器（Intent-to-Spec Compiler），也是下游 Agent 执行前的需求诊断与质量门禁。**

它把用户的粗糙想法，通过澄清、研究、多视角审查、冲突处理和评测，转换成可验证、可追溯、可交接的任务规格。

建议用一句话表达产品价值：

> PMind 将模糊产品想法转化为有证据、有边界、有验收标准、能被 Agent 或团队可靠执行的 Prompt Package。

### 2.2 核心价值链

```text
Idea
  → Evidence
  → Product Spec
  → Executable Prompt Package
  → Evaluation
  → Handoff
```

第一阶段重点解决三个问题：

1. 用户不知道自己的需求缺少什么信息。
2. 用户不知道哪些 GitHub 项目、Skill、框架或行业实践真正相关。
3. 用户无法判断一个“看起来专业”的提示词是否真的可执行、可验收。

### 2.3 建议的北极星指标

**首次交付成功率（First-pass Delivery Success）**：Prompt Package 被下游 Agent 或团队第一次接收后，无需大规模返工即可完成或进入有效实施的比例。

配套指标：

- 下游 Agent 首次完成率；
- 澄清轮数和返工轮数的下降幅度；
- 从想法到可交接规格的时间；
- 引用覆盖率和证据有效率；
- 验收用例 / Eval 通过率；
- 用户对最终规格的接受率；
- 单任务成本、延迟和人工介入率。

## 3. PMind 的标准产物：Prompt Package

最终输出不应只有一段“优化后的 Prompt”，而应是结构化、可机器读取又可供人审阅的 Prompt Package。建议至少包含：

1. 原始需求和问题陈述；
2. 目标用户、使用场景和预期结果；
3. 目标、范围与非目标；
4. 业务、技术、数据、合规和交付约束；
5. 已知事实、假设、未知项和待确认项；
6. 多轮澄清记录与关键决策理由；
7. 外部证据、引用、版本、许可证和可信度；
8. 推荐的 Skill、工具、Agent 能力和框架；
9. 优化后的 system / developer / user 提示词或等效的执行指令；
10. 输入、输出 Schema 和错误处理约定；
11. 验收标准、Eval 数据、测试用例和评分规则；
12. 风险、权限边界、审批点和人工介入点；
13. 面向后续 Agent、研发团队或其他系统的交接说明。

初期 PMind 应聚焦“优化、验证与交接”，不默认自动执行具有风险的下游操作。执行可以作为后续受控能力接入。

## 4. Skill、Agent、Service 与 Reference 的职责边界

| 层级 | 适合承担的职责 | 不适合承担的职责 |
| --- | --- | --- |
| Skill | 稳定、可复用的方法论，如需求发现、JTBD、PRD、RICE、风险识别、验收标准 | 动态长流程编排、强安全隔离、租户权限 |
| Agent | 缺口分析、动态追问、检索、综合判断、多角色协作和结果编译 | 单独承担不可绕过的企业安全控制 |
| Service | 鉴权、租户隔离、审计、预算、工具白名单、数据策略、版本发布 | 依赖自然语言提示保证所有安全性 |
| Reference | 保存有来源的外部证据、仓库、Skill、框架文档、许可证与分析 | 将未经审查的外部内容直接作为可信指令执行 |

关键原则：

- Skill 是方法，不是完整产品平台。
- Agent 是动态协调器，不是安全边界。
- 企业级硬控制必须由代码、服务和基础设施实现。
- Reference 是证据库，不是随意复制的代码仓库集合。

## 5. 建议的端到端工作流

### 5.1 八个阶段

1. **意图分类**：判断任务属于产品探索、需求定义、竞品分析、技术选型、Prompt 设计、交付规划或其他类型。
2. **缺口评分**：从用户、场景、目标、范围、约束、证据、风险、验收等维度判断信息完整度。
3. **自适应追问**：每轮优先询问 1–3 个信息增益最高的问题，避免一次抛出长问卷。
4. **证据检索**：按需搜索 GitHub、Skills、官方文档、框架、竞品和行业材料，并记录出处。
5. **多视角评审**：从用户、商业、技术、数据、安全、交付、增长和运营等角度审视需求。
6. **冲突处理**：识别目标冲突、范围冲突、成本冲突、证据冲突和不同角色结论冲突。
7. **规格编译**：生成结构化 Prompt Package，而不是只生成自然语言长文。
8. **评测与交接**：运行质量评分、Eval、风险检查，再交给选定的下游执行者。

### 5.2 停止追问规则

满足以下条件时应停止追问并继续生成：

- 关键维度已经达到最低完整度阈值；
- 剩余未知信息不会实质改变方案；
- 无法确定的信息已被明确标记为假设；
- 重大风险和权限需求已经向用户披露；
- 继续提问的预期信息增益低于用户的时间成本。

### 5.3 多视角不是简单多 Agent 投票

每个视角需要明确：输入、责任、输出 Schema、置信度和证据要求。最终由一个综合阶段处理冲突，保留少数意见和不确定性，不能用“多数票”掩盖高风险问题。

## 6. 用户画像与切入顺序

建议优先级：

1. **AI 原生独立开发者 / 创业者**：已经在使用编码 Agent，但需求经常不完整，愿意快速尝试新工作流。
2. **产品经理 / AI 产品经理 / 解决方案架构师**：需要把业务需求可靠交给 AI 或研发团队。
3. **产品负责人 / Product Ops 团队**：关心模板、组织上下文、复用、版本和协作。
4. **企业 AI 平台团队**：关心治理、审计、权限、模型路由、知识隔离和私有部署。

首个市场可聚焦“正在使用 Codex、Claude Code、Cursor 等编码 Agent 的产品经理、创业者和技术负责人”。他们的问题强、反馈周期短，也更容易衡量下游首次完成率。

长期差异化不应是“又一个完整产品管理平台”，而是：

> 跨平台的需求质量门禁：把模糊意图转成可执行、可测试、可追溯的 Agent 交接包。

## 7. 商业化趋势与竞争观察

### 7.1 市场趋势

- 单纯的文档生成和 Prompt 润色正在商品化。
- 更有壁垒的能力是组织上下文、证据、协作、版本和全生命周期闭环。
- 企业客户更看重引用、权限、审计、SSO、数据边界和部署选项。
- 产品形态正在从“Prompt Engineering”转向“Eval 驱动的规格与 Agent 配置”。
- MCP、API 和标准化导出会成为 PMind 向执行 Agent 交接的重要方式。
- 真正可收费的价值不是多生成一份 PRD，而是减少返工、提高首次完成率、缩短想法到交付的时间，并沉淀组织知识。

### 7.2 竞品观察

Productboard Spark 表明市场已经从“帮助写 PRD”向以下方向扩展：

- 持久化的组织上下文；
- 来源引用与可追溯性；
- 协作与版本历史；
- 代码库和工作上下文集成；
- 通过 MCP 等机制交接；
- 上线后的持续评估。

参考：[Productboard Spark](https://www.productboard.com/product/spark/)

ChatPRD 可作为面向个人和团队的价格参照。2026-08-21 快照为：Free；Pro 约 15 美元/月（年付 179 美元）；Teams 约 29 美元/席位/月（年付 349 美元）；Enterprise 定制。实施商业方案时必须重新核验。

参考：[ChatPRD Pricing](https://www.chatprd.ai/pricing)

### 7.3 初步商业模式

建议采用 Open Core / 分层订阅：

- **Free / Local**：本地 Skill、基础模板、有限任务和导出。
- **Pro**：约人民币 99–199 元/月，提供深度研究、更多项目记忆、评测和高级模型。
- **Team**：约人民币 299–599 元/席位/月，提供团队上下文、版本、协作、模板和基础治理。
- **Enterprise**：定制价格，提供私有化、BYOK、SSO、审计、数据隔离、白名单和专属集成。
- **Usage Add-on**：深度研究、批量 Eval、高成本模型和大规模代码库分析按量计费。

以上是探索区间，不是最终定价。

## 8. 成本估算与周期

### 8.1 模型与搜索成本快照

根据 2026-08-21 的 OpenAI 官方定价快照：

- GPT-5.6 Luna：输入约 0.20 美元 / 百万 token，输出约 1.20 美元 / 百万 token；
- GPT-5.6 Terra：输入约 2 美元 / 百万 token，输出约 12 美元 / 百万 token；
- Web Search：约 10 美元 / 1000 次调用，另计内容 token。

参考：[OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)

按“Luna 预处理 + Terra 综合 + 约 5 次搜索”的典型多轮任务粗估：

- 基础任务：约 0.10–0.30 美元 / 次；
- 深度研究或带 Eval：约 0.30–1.50 美元 / 次；
- 大代码库、多模型或长上下文任务：可能达到 2 美元以上 / 次。

这些只是推导用假设，不包括服务器、向量数据库、日志、支付、客服、人力和企业安全成本。早期最大的投入通常不是 token，而是产品与工程人力、真实评测数据、安全治理和集成维护。

### 8.2 建议周期

| 阶段 | 时间 | 目标 |
| --- | --- | --- |
| Skill-only Concierge | 1–2 周 | 用 20–50 个真实需求验证追问框架和 Prompt Package |
| Agent MVP | 4–6 周 | 实现动态追问、检索、引用、规格编译和基础交接 |
| Beta | 8–12 周 | 加入 Eval、版本、项目记忆和标准化导出 |
| Team / Enterprise | 3–6 个月 | 加入协作、权限、审计、私有部署和企业集成 |

周期取决于团队人数、首个集成平台、真实用户获取速度和企业要求，不应在技术栈确定前承诺固定发布日期。

## 9. 主要难点、风险与缓解策略

| 难点 / 风险 | 影响 | 初步缓解策略 |
| --- | --- | --- |
| Prompt / 规格没有统一真值 | 难以证明“优化”真的更好 | 用下游任务成功率和真实 Eval 衡量，而非只做语言评分 |
| 追问过多与信息缺失冲突 | 用户流失或输出不可执行 | 信息增益排序、每轮 1–3 问、明确停止规则 |
| GitHub / Skill 恶意、过时或许可证不兼容 | 注入、供应链、合规风险 | 来源追踪、许可证审查、允许列表、固定版本、安全扫描 |
| 企业数据经搜索、日志或上下文泄露 | 严重合规风险 | 数据分类、脱敏、最小化、租户隔离、BYOK、审计和禁搜策略 |
| 多 Agent 增加成本、延迟和不确定性 | 商业毛利和体验下降 | 小模型路由、并行上限、缓存、预算门禁、单 Agent 优先 |
| 不同行业验收标准差异大 | 通用模板失效 | 领域包、行业专家复核和垂直 Eval 数据集 |
| 输出“精致但幻觉” | 用户误信错误结论 | 强制引用、事实/推断/建议分层、置信度、人工审批 |
| 供应商接口和功能变化 | 维护成本高 | Provider-neutral 的接口、版本锁定、适配器和回归测试 |

特别注意：开放 Skill 和外部仓库内容都可能包含提示注入或数据外传指令。不能把任意第三方 Skill 直接暴露给最终用户或高权限 Agent；应人工审查、精选、允许列表化，并把高风险操作置于显式审批之后。

Skill 指令本质上是提示级方法，不是不可绕过的安全策略。企业安全必须下沉到代码和基础设施。

## 10. MVP 验证方案

首轮建议累计完成 30 个成对案例：先运行 10 个合成种子案例校准协议，再收集 20 个真实、尚未解决的任务；覆盖产品探索、功能需求、竞品研究、技术选型和下游编码交接。该执行口径由 `reference/research/next-execution-stage-2026-08-21.md` 更新并取代早期“30 个真实任务”的探索假设。

对每个任务保留：

- 原始用户输入；
- 未经 PMind 处理时的下游结果；
- PMind 澄清记录和 Prompt Package；
- 使用 PMind 后的下游结果；
- 首次完成率、澄清轮数、总耗时、成本、用户评分；
- 失败原因和人工修正内容。

第一阶段成功信号：

- 下游首次完成率有稳定提升；
- 澄清和返工轮数下降；
- 从想法到可执行交接的时间下降至少 50%；
- 用户愿意保存、复用或分享 Prompt Package；
- 质量提升可以由 Eval 或实际交付证明，而不仅是主观“写得更专业”。

## 11. 候选技术与开源项目

以下项目是候选参考，不代表已经采用，也不代表可以直接复制代码。

### 11.1 Agent 编排

- [OpenAI Agents SDK](https://github.com/openai/openai-agents-python)：Agent、工具、handoff、guardrails、session 和 tracing。适合作为 MVP 的轻量编排候选。
- [LangGraph](https://github.com/langchain-ai/langgraph)：适合需要持久状态、人工介入、失败恢复和复杂状态机的阶段。MVP 不必因“功能丰富”而提前引入。

### 11.2 Prompt 与 Agent 评测

- [Promptfoo](https://github.com/promptfoo/promptfoo)：可用于 Prompt / 模型比较、红队、回归测试和 CI，建议作为早期评测基线候选。
- [OpenAI Agent Evals](https://developers.openai.com/api/docs/guides/agent-evals)：可先使用 trace grading，再逐步形成 datasets 与 evals。
- [DSPy](https://github.com/stanfordnlp/dspy)：适合在已有指标和数据后做程序化 Prompt 优化，建议放到实验阶段。
- [Microsoft PromptWizard](https://github.com/microsoft/PromptWizard)：其 generate–score–critique–synthesize 思路可供参考，不建议成为核心强依赖。

OpenAI Prompt Optimizer 的现有资料显示，数据集驱动的 legacy optimizer 计划在 2026-10-31 进入只读、2026-11-30 关闭。无论届时状态如何，PMind 都应设计供应商中立的 `Evaluator` / `Optimizer` 接口，并在实施前重新核验官方信息。

参考：[OpenAI Prompt Optimizer](https://developers.openai.com/api/docs/guides/prompt-optimizer)

### 11.3 可观测性和持续质量

- [Langfuse](https://github.com/langfuse/langfuse)：Prompt、trace、dataset、Eval 和成本可观测性，适合 Beta 或企业阶段评估。

### 11.4 Skill 发现与管理

- [Vercel Skills CLI](https://github.com/vercel-labs/skills)：可参考 Skill 的发现、安装和版本管理方式。
- [mattpocock/skills](https://github.com/mattpocock/skills)：可作为 PMind 工程实施的方法库和工程工作流基础，详细结论见后文。

## 12. Reference 资料库设计

建议结构：

```text
reference/
├── registry.yaml
├── github/
│   └── owner__repo/
│       ├── source.yaml
│       ├── README.md
│       ├── LICENSE
│       └── analysis.md
├── skills/
│   └── skill-name/
│       ├── SKILL.md
│       ├── source.yaml
│       └── security-review.md
├── frameworks/
│   └── framework-name/
│       ├── source.md
│       └── adaptation.md
└── snapshots/
    └── YYYY-MM-DD/
```

建议每份 `source.yaml` 记录：

- 原始 URL；
- commit SHA、tag 或发布版本；
- 获取日期；
- 许可证及再分发 / 修改条件；
- 可信度等级；
- 安全扫描和人工审查状态；
- PMind 实际借鉴了哪些思想、文档或代码；
- 后续更新与淘汰策略。

不要为了“有资料”而盲目复制整个仓库。优先保存必要的源信息、许可证、分析和经许可的局部内容；代码复用必须保留归属并符合许可证。

## 13. 项目仓库的候选结构

以下只是探索草案，尚未创建：

```text
.agents/skills/              # PMind 精选和自研 Skills
AGENTS.md                    # 仓库级 Agent 工作规则
CONTEXT.md                   # 领域词汇、边界和核心上下文
docs/agents/                 # Agent 与工程工作流配置
docs/adr/                    # 架构决策记录
reference/                   # 外部资料及来源审查
skills/pmind/                # PMind 产品 Skill
agents/                      # 动态编排和角色定义
src/domain/                  # 领域模型和核心业务逻辑
evals/                       # 数据集、评分规则和回归测试
```

结构应在明确首个实现语言、运行形态和下游平台后再定稿。

## 14. 使用 mattpocock/skills 管理项目的探索

### 14.1 项目概况

仓库：[mattpocock/skills](https://github.com/mattpocock/skills)

探索快照：

- 许可证为 MIT；
- 设计理念是 small、adaptable、composable，不强行接管整个流程；
- README 提供 `npx skills@latest add mattpocock/skills` 的安装方式；
- 安装后 Skill 会作为可编辑文件复制到本地，并可通过 `npx skills update` 更新；
- 快照时原生 Codex plugin 仍在路线图中，但部分 Skill 已包含 `agents/openai.yaml`；
- 这些状态实施前必须再次从仓库核验。

### 14.2 适配结论

**可以使用，但不应让它管理 PMind 的全部产品能力。**

它适合作为 PMind 的“工程操作系统 / 方法库”，覆盖需求澄清、领域建模、研究、规格、任务拆分、TDD、调试、架构、代码评审和交接；但它不能替代 PMind 的核心产品能力，也不能承担 Prompt 优化、Agent Eval、企业权限、Reference 安全和商业工作流。

推荐关系：

```text
PMind 产品层
├── 意图诊断、动态追问、证据检索、Prompt Package、Eval、治理
└── 工程实施层
    ├── auto-coding：权限、风险路由、实现和验证纪律
    └── mattpocock/skills：可组合的工程方法
```

规则优先级：

```text
系统 / 开发者规则
  > 用户明确指令
  > 仓库 AGENTS.md 与安全 / 授权规则
  > auto-coding 的风险与权限流程
  > mattpocock/skills 的补充方法
```

### 14.3 适合 PMind 的能力

已观察到的相关 Skills 包括：

- 产品与需求清晰度：`grill-me`、`grill-with-docs`；
- 领域模型：`domain-modeling`；
- 研究：`research`；
- 规格：`to-spec`；
- Tracer-bullet 任务拆分：`to-tickets`；
- 实施与 TDD：`implement`、`tdd`；
- 故障诊断：`diagnosing-bugs`；
- 架构与代码库设计：`codebase-design`、`improve-codebase-architecture`；
- 代码评审：`code-review`；
- 交接：`handoff`；
- 其他用户调用型能力：`ask-matt`、`triage`、`setup-matt-pocock-skills`、`wayfinder`；
- 其他模型调用型或生产力能力：`prototype`、`research`、`resolving-merge-conflicts`、`wizard`、`teach`、`questionnaire`、`wait-what`、`grilling`、`writing-for-agents`。

列表可能随上游仓库变化，安装前应以当前 README 和各 `SKILL.md` 为准。

### 14.4 建议首批精选安装

在用户明确授权后，建议先审查并选择：

1. `setup-matt-pocock-skills`
2. `grill-with-docs`
3. `domain-modeling`
4. `research`
5. `to-spec`
6. `to-tickets`
7. `tdd`
8. `diagnosing-bugs`
9. `codebase-design`
10. `code-review`
11. `handoff`

建议暂缓：

- `triage`：公开仓库已创建，但尚未配置 Issue / 标签工作流；
- `wayfinder`：空仓库阶段暂不需要大型代码库导航；
- `improve-codebase-architecture`：尚无现有架构可改进；
- `prototype`：等进入具体原型任务时再决定；
- `resolving-merge-conflicts`：出现真实场景后再启用；
- `implement`：应先完成授权语义的本地化改造。

### 14.5 必须做的本地化改造

1. 上游 `implement` 存在自动提交倾向；PMind 必须改成“只有用户明确授权时才提交”。
2. `to-spec` 可能直接发布到任务系统并标记 ready-for-agent；`to-tickets` 可能直接创建 Issue。PMind 默认只生成本地草稿，任何外部写入都需审批。
3. 上游跨 Skill 调用中的 `/tdd`、`/code-review` 或“Skill tool”等语法，需要按 Codex 实际调用方式核验并改写为 `$skill` 或明确指令。
4. `research` 应将资料写入 `reference/research/`，记录来源、日期、版本、许可证和可信度；不得执行任意外部代码。
5. 必须写明规则优先级，Matt Pocock Skills 只是方法补充，不能覆盖 PMind 的安全和授权规则。
6. 采用精选、审查、固定版本的本地副本，不启用无审查的自动更新。

相关上游文件：

- [setup-matt-pocock-skills/SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/SKILL.md)
- [implement/SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/implement/SKILL.md)
- [to-spec/SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md)
- [to-tickets/SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md)

### 14.6 官方 Codex Skill 约束对方案的影响

根据 OpenAI Build Skills 资料：

- Skill 是带 `SKILL.md` 的版本化目录包，可包含 scripts、references、assets 和可选的 `agents/openai.yaml`；
- 仓库级 Skill 可放在 `.agents/skills/`；
- Skill 可以通过 `$skill` 显式调用，也可以按描述隐式触发；
- 可使用 `allow_implicit_invocation: false` 限制只允许显式调用；
- Plugin 适合分发一组 Skills、Agents 与 MCP 能力；
- Skills 采用渐进式披露，但初始 Skill 列表仍有上下文预算；资料提到约为上下文的 2% 或 8000 字符（具体行为应以当前官方文档为准）。安装太多 Skill 可能导致部分 Skill 被缩短或遗漏。

因此 PMind 应精选安装，而不是整包全部启用。

参考：[OpenAI Build Skills](https://learn.chatgpt.com/docs/build-skills)

### 14.7 建议的受控工作流

```text
探索
  → grill-with-docs
  → CONTEXT.md / ADR / reference

规格
  → to-spec
  → 人工确认
  → 本地 spec

拆解
  → to-tickets
  → tracer-bullet tasks
  → 本地文件或经授权的 GitHub Issues

实施
  → auto-coding 权限与风险路由
  → tdd / codebase-design
  → code-review

交接
  → handoff
```

### 14.8 当前仓库的建议默认配置

项目引导时没有 GitHub remote 和 Issue 系统，因此第一阶段采用：

- Agent 指令文件：`AGENTS.md`；
- Tracker：本地 Markdown；
- 临时任务：`.scratch/<feature>/issues/`；
- 领域词汇和核心上下文：`CONTEXT.md`；
- 架构决策：`docs/adr/`；
- Agent 配置：`docs/agents/`；
- 外部研究：`reference/`；
- 精选 Skill：`.agents/skills/`；
- Skill 版本策略：复制到仓库、记录上游 commit、人工审查后更新。

公开远程仓库现已建立，但本地 Markdown 仍是默认 Tracker。等 Issue
模板、标签和协作方式确定后，再决定是否切换为 GitHub Issues。

## 15. 当前 Git 与开发环境状态

工作目录：

```text
/Users/yuzheng/Computeracy/Zhenkun26-GitHub/PMind
```

已完成：

- 使用 `git init -b main` 初始化 Git；
- 当前分支为 `main`；
- Git 识别该目录为有效工作树；
- 初始化时沙箱最初阻止写入 `.git`，在用户批准相应权限后成功完成。

当前状态（2026-08-21 公开归档后）：

- 公开 GitHub 仓库：`https://github.com/zhenkun26/PMind`；
- `origin`：`https://github.com/zhenkun26/PMind.git`；
- 默认分支：`main`；
- Git 历史从本次项目引导归档提交开始；
- 已在 `.agents/skills/` 安装并安全本地化 12 个精选第三方 Skills；
- 已创建 `AGENTS.md`、`CONTEXT.md`、`docs/`、`reference/`、`evals/` 和本地 Tracker 骨架；
- 尚未创建产品工程代码或依赖清单；
- 来源、MIT 许可证与安全审查位于 `reference/github/mattpocock__skills/`。

环境快照：

- Node：`/Users/yuzheng/.nvm/versions/node/v24.16.0/bin/node`；
- Node 版本：`v24.16.0`；
- npm / npx 版本：`11.13.0`。

## 16. 已定、暂定与未决事项

### 16.1 已形成共识的方向

- 产品名为 PMind。
- 不把产品限制为 Prompt 润色器。
- 核心产物是可验证、可追溯、可交接的 Prompt Package。
- MVP 先做需求优化和交接，不默认执行高风险下游动作。
- `reference/` 需要来源、版本、许可证和安全审查。
- `mattpocock/skills` 可作为工程方法库，但不能管理整个 PMind 产品。
- Skill 的使用必须服从仓库授权、安全和评测规则。
- 以真实下游交付成功率评估产品，而不是只看文案质量。

### 16.2 暂定方案

- 初始客户：使用编码 Agent 的产品经理、创业者和技术负责人；
- Agent 编排：优先评估 OpenAI Agents SDK，复杂状态出现后再评估 LangGraph；
- Eval：优先评估 Promptfoo + trace grading；
- 工程方法：精选和本地化 mattpocock/skills；
- 工作方式：本地 Markdown Tracker，未来再接 GitHub Issues；
- 商业模式：Open Core + Pro / Team / Enterprise + 按量能力。

### 16.3 仍需用户和产品验证决定

1. PMind 首版是 Codex-first，还是一开始就供应商中立？
2. 首个下游交接目标是编码 Agent、产品研发团队、自动化工作流还是多个目标？
3. 首版面向个人、团队还是企业试点？
4. 产品界面是 CLI、Codex Skill、Web App、API，还是组合形态？
5. 默认使用云端模型、BYOK、本地模型还是混合路由？
6. 中文优先、英文优先还是双语？
7. 是否允许 PMind 自动执行低风险下游操作？审批粒度如何？
8. 技术栈、数据库、部署环境和可观测性平台如何选型？
9. 何时配置 GitHub Issue 模板、标签和 CI？
10. 首批实际安装哪些 mattpocock Skills，采用哪个上游 commit？

## 17. 下一步授权门槛与建议顺序

本文最初写入不等于获得后续操作授权。用户随后已授权并完成第 1–4
项的本地、可审查工作；其余操作仍应逐项明确授权：

1. 已完成：核验并下载 `mattpocock/skills` 的候选 Skill；
2. 已完成：创建 `.agents/skills/`、`AGENTS.md`、`CONTEXT.md`、`docs/`、`reference/` 等骨架；
3. 已完成：对候选 Skill 做许可证、提示注入、外部写入和自动提交审查；
4. 已完成：生成 PMind 本地化副本和版本清单；
5. 后置到 Validation Gate 通过后：选择 MVP 技术栈并初始化依赖；
6. 已完成第 0 阶段：建立 Eval 数据结构和 10 个合成种子案例；20 个真实任务仍待招募和执行；
7. 已授权执行：创建第一个 Git commit；
8. 已完成 remote 创建并已授权执行 push；GitHub Issues 仍未启用。

建议授权后的第一批工作范围：

```text
只做本地、可审查、可回退的项目引导：
- 建立 AGENTS.md / CONTEXT.md / docs / reference / evals 骨架；
- 精选下载 mattpocock Skills，但不直接运行外部写入流程；
- 记录上游 commit、许可证和安全审查；
- 完成 PMind 授权语义的本地化；
- 不自动提交、不推送、不创建远程 Issue。
```

建议该阶段完成审查后再由用户决定是否提交，候选提交信息：

```text
chore: bootstrap PMind agent workflow
```

本文本身的候选提交信息：

```text
docs: capture PMind product and implementation exploration
```

## 18. 外部资料索引

以下资料均为探索来源，实际采用前需重新核验版本、许可证、定价和安全状态：

- [Productboard Spark](https://www.productboard.com/product/spark/)
- [ChatPRD Pricing](https://www.chatprd.ai/pricing)
- [OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)
- [OpenAI Build Skills](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI Agent Evals](https://developers.openai.com/api/docs/guides/agent-evals)
- [OpenAI Prompt Optimizer](https://developers.openai.com/api/docs/guides/prompt-optimizer)
- [OpenAI Agents SDK](https://github.com/openai/openai-agents-python)
- [Promptfoo](https://github.com/promptfoo/promptfoo)
- [DSPy](https://github.com/stanfordnlp/dspy)
- [Microsoft PromptWizard](https://github.com/microsoft/PromptWizard)
- [LangGraph](https://github.com/langchain-ai/langgraph)
- [Langfuse](https://github.com/langfuse/langfuse)
- [Vercel Skills CLI](https://github.com/vercel-labs/skills)
- [mattpocock/skills](https://github.com/mattpocock/skills)

## 19. 给后续 Agent 的最短恢复指令

```text
先完整阅读仓库根目录 PMIND_EXPLORATION.md。
PMind 当前处于 Validation Sprint 第 1 阶段：公开仓库、12 个本地化 Skill、产品契约、10 个未运行种子案例和 3 个校准 Fixture 已存在。
先运行 ruby scripts/validate_evals.rb，并读取 evals/calibration/wave-01.yaml 与 evals/fixtures/README.md。
不得把 Fixture 基础自检当成 PMind 效果证据；当前 Wave 仍因角色、执行器配置和双臂隔离工作区未就绪而 blocked。
Case Schema 现为 0.2.0，Acceptance Result Schema 为 0.1.0；运行产物路径、成功公式以及 consensus / needs_adjudication / adjudicated 三态已由验证器覆盖，但当前仍为 0 条运行和 0 条验收结果。
Prompt Package v0 的机器契约位于 schemas/prompt-package-v0.yaml，可用 ruby scripts/validate_prompt_package.rb PATH 做只读校验；不得把 test/fixtures 下的合成 Package 当作真实产出。
Clarification Session v0 的机器契约位于 schemas/clarification-session-v0.yaml，可用 ruby scripts/validate_clarification_session.rb SESSION 做状态校验，或加入 --prompt-package PACKAGE 校验编译 lineage；不得虚构用户答案、授权、假设或决策来让会话进入 ready_to_compile。
隔离工作区准备器和统一 preflight 已实现并验证，但未保留任何真实 Wave 运行副本，也未虚构人员或模型配置。下一步是分配四个互异角色并补齐、冻结 Executor Profile，再在仓库外创建同源双臂副本并要求 preflight 输出 READY；不要擅自提交、推送、安装依赖或写入外部系统。
```

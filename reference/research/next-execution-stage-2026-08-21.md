# PMind 下一执行阶段探索：Validation Sprint

- 状态：第 0 阶段已归档；第 1 阶段校准准备完成但尚未满足启动门槛
- 研究日期：2026-08-21
- 资料检索日期：2026-08-21
- 适用范围：PMind 从探索仓库进入第一个可验收产品阶段
- 核心决策：先验证 Prompt Package 的产品价值，再选择 Agent 框架和应用技术栈

## 1. 执行摘要

PMind 的下一阶段不应是“搭建完整多 Agent 产品”，而应是一个 **7–10 个工作日的 Validation Sprint（人工增强验证冲刺）**。

本阶段要回答的唯一核心问题是：

> 相比用户直接把原始想法交给编码 Agent，PMind 的澄清、研究、多角度审查和 Prompt Package，能否以可接受的时间与成本，显著提升下游首次交付成功率？

当前仓库已经具备项目语境、Skill 工作流、参考资料治理和初步评测框架，但尚没有证明用户愿意采用该流程，也没有证明它能降低返工。因此，先写 Agent 编排代码会把尚未验证的产品假设固化为接口、状态机和基础设施。

建议用现有 Codex + 本地 Skills 作为“后台人工系统”运行 PMind 服务，完成 30 个成对案例后再决定是否进入 Agent MVP。

## 2. 为什么这是当前最大的不确定性

### 已经具备

- 项目目标、边界和核心领域词汇已经写入仓库。
- 已本地化研究、领域建模、代码库设计、TDD、诊断和评审等 Skills。
- 已定义初步评测方向：首次交付成功率、返工次数、完成时间、引用有效性、接受度、成本和延迟。
- `reference/` 已具备来源登记和研究归档能力。

### 尚未证明

- 哪一类用户会反复使用 PMind，而不是只让通用模型“帮我优化提示词”。
- 哪些澄清问题真正提升结果，哪些只是增加摩擦。
- Prompt Package 的最小必需字段是什么。
- “多角度”需要哪些稳定审查视角，以及何时应该停止扩展。
- GitHub/Skill/框架研究对下游结果产生多大增益。
- 首次成功率提升是否足以覆盖额外时延、模型成本和用户认知成本。
- 是否需要多 Agent；即使需要，也尚未确定由经理 Agent 集中合成，还是将会话交接给专家。

这些是产品真值问题，不能通过选择框架来回答。

## 3. 三条路线比较

| 路线 | 周期估算 | 主要产出 | 能回答的问题 | 主要风险 | 建议 |
| --- | ---: | --- | --- | --- | --- |
| A. 验证优先 | 7–10 个工作日 | 质量契约、人工运行手册、30 个对照案例、决策报告 | 用户与下游结果是否真正获益 | 需要人工操作和招募真实案例 | **立即执行** |
| B. 框架优先 | 3–5 个工作日形成骨架 | Agent SDK/状态机/CLI 骨架 | 技术能否跑通 | 过早固化未经验证的字段和流程 | 推迟到验证通过后 |
| C. 完整 Agent MVP | 4–6 周 | 多 Agent、搜索、会话、评测、追踪和界面 | 端到端系统是否可用 | 成本高，产品假设和工程风险同时叠加 | 当前不执行 |

周期是单名熟悉 AI 工程的产品工程师、现有仓库基础上的方向性估算，不是供应商报价。

## 4. Validation Sprint 的可逆默认定位

为了让实验可执行，本阶段采用以下默认值。它们是实验约束，不是永久产品承诺。

### 目标用户

首批用户限定为：已经使用 Codex、Claude Code 等编码 Agent，但经常因为需求模糊、缺少约束或验收标准而返工的 AI 原生产品经理、创始人和技术负责人。

### 下游目标

- 第一类任务：软件产品功能从模糊想法到可交付编码任务。
- 第一下游执行器：以 Codex 为主进行对照实验。
- Prompt Package 的语义字段保持供应商中立，避免成为 Codex 私有格式。

### 交互和交付

- 中文优先对话；未来结构化字段使用稳定英文键名。
- 仓库内/会话式交互，不建设 Web UI。
- PMind 只交付 Prompt Package，不自动启动下游编码、提交、部署或外部写入。
- 每轮最多提出 1–3 个高信息增益问题，并设置停止规则。
- 所有未知信息必须标记为“未知”或“假设”，不得悄悄补全为事实。

## 5. 本阶段范围

### 必须产出

1. **Prompt Package v0 质量契约**
   - 原始意图与目标
   - 用户/业务上下文
   - 范围与非目标
   - 约束、依赖和现状证据
   - 研究发现及来源
   - 决策、假设和未决问题
   - 建议方案与替代方案
   - 验收标准和验证方式
   - 风险、审批点和交接说明

2. **澄清策略 v0**
   - 信息缺口维度
   - 问题优先级计算原则
   - 每轮问题上限
   - 停止、降级和用户拒答规则

3. **审查视角 v0**
   - 用户价值与商业目标
   - 产品范围与边界
   - 技术可行性与复用
   - 数据、安全和合规
   - 成本、周期和运营
   - 可测试性与验收

4. **Concierge Runbook v0**
   - 使用现有 Skills 的人工执行顺序
   - 何时搜索 GitHub、Skill、框架和官方资料
   - 来源可信度、引用和 `reference/` 归档规则
   - 何时终止研究，避免无限扩展
   - 人工审批和交付清单

5. **评测案例与评分规则 v0**
   - 10 个覆盖不同模糊度与风险的种子任务
   - 20 个来自 5–10 名目标用户的真实任务
   - 每个任务保存原始提示、PMind 过程、最终 Package、下游结果、修正轮次、时间和成本
   - 基线组与 PMind 组尽量使用同一模型、环境和资源权限

6. **阶段决策报告**
   - 量化结果、失败模式、用户反馈
   - 继续、缩窄或停止的建议
   - 若继续，再提交 Agent MVP 与技术选型提案

### 明确不做

- 不建设 Web UI、账号、团队、多租户、计费或管理后台。
- 不安装 Agent 框架、评测框架、向量数据库或可观测平台。
- 不做多 Agent 扇出、长期记忆、自动下游执行或生产部署。
- 不为所有行业和所有提示词类型设计通用本体。
- 不以生成内容长度或“看起来专业”作为成功指标。

## 6. 建议执行顺序

### 第 0 阶段：冻结实验契约（1–2 天）

- 编写 Prompt Package v0、澄清策略、审查视角和评分 Rubric。
- 定义基线流程与 PMind 流程，确保比较公平。
- 选择 10 个种子案例，先进行一次小规模评分校准。
- 明确哪些结果需要人工盲评，哪些可自动计算。

退出条件：两名评审能依据同一 Rubric 独立判断“首次交付是否成功”，且对必填字段没有重大歧义。

### 第 1 阶段：种子案例校准（2–3 天）

- 对 10 个种子任务分别运行原始提示基线和 PMind 流程。
- 记录耗时、模型/搜索成本、问题轮数、下游返工和失败类型。
- 只修改契约和流程，不写产品运行时代码。

退出条件：流程可以重复执行，数据字段完整，主要失败能够被分类。

### 第 2 阶段：真实用户验证（3–5 天）

- 招募 5–10 名目标用户，收集 20 个真实、尚未被解决的任务。
- 使用同一实验协议运行成对对照。
- 收集用户对问题相关性、等待成本、可理解性和交付信心的反馈。

退出条件：累计至少 30 个成对案例，且不存在大面积缺失数据。

### 第 3 阶段：决策（1 天）

- 汇总主要指标和失败模式。
- 判断增益来自澄清、研究、审查、结构化交付中的哪一部分。
- 做出进入 Agent MVP、缩窄后复测或停止投资的决定。

## 7. 指标与决策门槛

以下门槛是 PMind 的首轮产品假设，不是行业标准；应在第 0 阶段冻结，避免观察结果后再调整标准。

### 主指标

- **首次交付成功率**：下游执行结果无需重大需求修正即可通过预先定义的验收标准。
- 建议继续投资门槛：PMind 组相对基线提升至少 **15 个百分点**，并且没有严重安全、隐私或错误事实回归。

### 护栏指标

- 重大返工轮次相对基线降低至少 25%。
- 从原始想法到可交接 Package 的中位时间不超过 45 分钟；同时记录与基线的净时间差。
- 100% Package 的必需字段有明确值，或明确标记未知/假设/不适用。
- 100% 外部事实性研究结论可追溯到来源。
- 100% 高风险外部动作以 Approval Point 显式呈现。
- 每个案例记录模型调用、搜索、人工操作时间和估算边际成本。
- 用户主观评分只作为辅助信号，不能替代下游任务结果。

### 决策规则

- **通过**：主指标达到门槛、护栏无严重回归，进入 Agent MVP 规格与技术选型。
- **混合**：有价值信号但未达门槛；仅调整一个主要变量，增加 10–15 个案例复测。
- **失败**：无稳定增益，或额外时间/成本超过用户可接受范围；停止框架投入，重新定位或终止。

样本量 30 只适合方向性产品决策，不能声称统计学上的普遍有效性。

## 8. 成本与人员

### 最小团队

- 1 名产品/AI 工程负责人：设计协议、运行流程、汇总结果。
- 1 名兼职评审：校准 Rubric 并对部分案例盲评。
- 5–10 名目标用户：提供真实任务与反馈。

### 成本构成

- 主要成本是 7–10 人日的产品与实验劳动。
- 模型和搜索成本应逐案例计量；在任务和模型尚未冻结前，不给出虚假的固定金额预测。
- 可为真实用户设置小额访谈或任务激励，金额由招募渠道和地区决定。
- 当前阶段无需承担应用托管、数据库、身份系统或生产可观测基础设施成本。

## 9. 验证通过后的技术含义

以下不是本阶段的实现承诺，而是通过质量门后可进入 ADR 的候选方向。

### 一手资料事实

- OpenAI Agents SDK 已提供 Agent、Runner、工具、guardrails、handoffs、sessions 和 tracing 等编排原语。
- SDK 文档区分两种多 Agent 方式：将专家作为工具，由经理 Agent 保留最终控制；或 handoff 后由专家接管后续会话。
- SDK 内置 tracing，可记录模型调用、工具调用、handoff 和 guardrail；文档同时提示敏感数据与 Zero Data Retention 的限制需要单独处理。
- SDK 的测试工具可以在不调用模型和网络的情况下验证工具执行、handoff、guardrail、重试与 session 行为；模型或网络拥有的行为仍需要真实适配器测试。
- OpenAI 的 Agent 评测指南建议调试阶段先观察 traces 和 trace grading；当“好”的定义稳定后，再转为可重复的数据集与 eval runs。
- Promptfoo 提供声明式的 prompts/providers/tests/assertions 配置、成本与 token 等结果字段，并提供 CI/CD 与 red-team 工作流。
- 截至检索日，OpenAI 已宣布旧 Evals 平台于 2026-06-03 弃用，计划 2026-10-31 转为只读、2026-11-30 关闭 Dashboard/API，并提供迁移到 Promptfoo 的官方指南。
- 截至检索日，OpenAI Agents SDK 最新核验版本为 Python `v0.22.0`（要求 Python 3.10+），Promptfoo 最新核验版本为 `0.122.0`（要求 Node 22.22.0+）；两个项目均采用 MIT 许可证。
- Promptfoo 的自定义 provider、assertion、transform 和 hook 以当前用户权限运行，不构成代码沙箱；不可信配置不能直接进入含密钥的 CI。

### 对 PMind 的推论

- 若验证通过，首版更适合使用 **单一经理 Agent + 专家作为工具**，因为 PMind 需要保留对最终 Prompt Package、统一质量门和审批点的控制；暂不需要专家接管整个对话。
- Python + OpenAI Agents SDK 是合理的首个运行时候选，但应在 Agent MVP ADR 中与 TypeScript/供应商中立方案比较。
- Promptfoo 适合在案例 Schema 与 Rubric 稳定后用于提示词/模型回归和 CI；现在安装只会自动化尚未稳定的判断标准。
- 可以借鉴 OpenAI 的 trace-first 评测方法，但不应采用即将关闭的旧 Evals API、Datasets Dashboard 或 hosted graders 作为 PMind 的长期评测存储。
- 若验证通过，可固定而不是追随 `latest` 的 Promptfoo 版本，并优先使用 JSON Schema、必填字段、禁止外部写入、工具/参数匹配等确定性断言；只有难以确定性判断的“规格可执行性”才增加经人工标签校准的 pass/fail 模型评分。
- tracing 应从开发环境开始，并显式配置敏感数据策略；不能默认把真实企业提示和工具输入广泛上传。
- Promptfoo 配置和其引用的自定义代码必须按可信代码审查；含密钥的 CI 不运行来自未受信 fork 的配置。
- LangGraph、DSPy、PromptWizard、Langfuse、向量数据库及多 Agent 扇出应按已观察到的具体失败模式引入，而不是作为项目起步清单。

## 10. 主要风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 评审知道实验分组 | 放大 PMind 效果 | 尽可能盲评最终结果，固定 Rubric |
| PMind 组获得更多时间/工具 | 对照不公平 | 同时记录资源差异，并报告净时间与成本 |
| 任务过于合成 | 无法代表购买场景 | 至少 20 个真实未解决任务 |
| 澄清问题过多 | 用户放弃 | 每轮 1–3 问、问题价值排序、允许跳过 |
| 研究无限扩展 | 延迟和成本失控 | 设来源优先级、时间盒与停止规则 |
| 企业数据进入追踪/第三方 | 隐私与合规风险 | 验证阶段使用授权数据，去标识化，外部写入需审批 |
| 只优化某个模型 | 商业可迁移性差 | 语义契约供应商中立，后续增加第二执行器验证 |

## 11. 一手资料索引

检索日期均为 2026-08-21。

- [OpenAI Agents SDK：Agent definitions](https://openai.github.io/openai-agents-python/agents/) — Agent、工具、guardrails、handoffs、sessions 等能力。
- [OpenAI Agents SDK：Quickstart](https://openai.github.io/openai-agents-python/quickstart/) — Runner、handoff 与 tracing 的基本流程。
- [OpenAI Agents SDK：Multi-agent orchestration](https://openai.github.io/openai-agents-python/multi_agent/) — agents-as-tools 与 handoffs 的控制权差异。
- [OpenAI Agents SDK：Tracing](https://openai.github.io/openai-agents-python/tracing/) — 默认 tracing、事件范围、敏感数据和 ZDR 注意事项。
- [OpenAI Agents SDK：Testing](https://openai.github.io/openai-agents-python/testing/) — 确定性内存测试工具的覆盖范围与边界。
- [OpenAI Agents SDK：Guardrails](https://openai.github.io/openai-agents-python/guardrails/) — 输入、输出和工具 guardrails 的运行语义。
- [OpenAI：Evaluate agent workflows](https://developers.openai.com/api/docs/guides/agent-evals) — traces、graders、datasets 与 eval runs 的采用顺序。
- [OpenAI：Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices) — 真实任务分布、持续评测、人工校准与多 Agent 评测原则。
- [OpenAI：Deprecations](https://developers.openai.com/api/docs/deprecations) — 旧 Evals 平台弃用及关闭时间表。
- [OpenAI Cookbook：Moving from OpenAI Evals to Promptfoo](https://developers.openai.com/cookbook/examples/evaluation/moving-from-openai-evals-to-promptfoo) — 官方迁移方向。
- [OpenAI：Using GPT-5.6](https://developers.openai.com/api/docs/guides/latest-model) — 代表性 eval、精简提示和单变量迭代建议。
- [OpenAI Agents SDK v0.22.0 release](https://github.com/openai/openai-agents-python/releases/tag/v0.22.0) — 核验版本。
- [Promptfoo configuration reference](https://www.promptfoo.dev/docs/configuration/reference/) — providers、prompts、tests、assertions 与结果字段。
- [Promptfoo red-team configuration](https://www.promptfoo.dev/docs/red-team/configuration/) — targets、plugins、strategies 与 purpose 配置。
- [Promptfoo：Evaluate OpenAI Agents Python](https://www.promptfoo.dev/docs/guides/evaluate-openai-agents-python/) — SDK trace 与 Promptfoo 断言的集成方式。
- [Promptfoo v0.122.0 release](https://github.com/promptfoo/promptfoo/releases/tag/0.122.0) — 核验版本。
- [Promptfoo security policy](https://github.com/promptfoo/promptfoo/security) — 自定义代码、CI、密钥和本地 UI 的安全边界。
- [Promptfoo GitHub repository](https://github.com/promptfoo/promptfoo) — 项目源码、CLI 和 CI/CD 能力入口。

## 12. 下一授权边界

如果负责人授权执行本建议，下一次工作应只创建 Validation Sprint 的规格与评测资产，不安装依赖、不实现 Agent 运行时。建议首批文件为：

- `docs/product/prompt-package-v0.md`
- `docs/product/clarification-policy-v0.md`
- `docs/product/review-lenses-v0.md`
- `docs/product/concierge-runbook-v0.md`
- `evals/schema/case-v0.yaml`
- `evals/rubrics/first-pass-success-v0.md`
- `evals/cases/seed/` 下的 10 个种子案例

完成并评审这些资产后，才能开始跑 30 个成对案例；达到决策门槛后，才进入 Agent MVP 技术选型和实现。

## 13. 执行状态（2026-08-21）

已完成第 0 阶段的本地资产：四份产品契约、案例 Schema、首次成功 Rubric 和 10 个合成种子案例。所有种子案例保持空 `run_records`，没有伪造基线或 PMind 结果；本阶段没有安装 Agent/Eval 框架，也没有执行外部写入。

下一质量门是由两名评审先用 3 个种子案例校准 Rubric 和角色隔离，再运行完整 10 案例。若无法提供独立案例主持人与第二评审，应把盲评和一致率标记为受限，而不能声称第 1 阶段通过。

已进一步创建 `calibration-001`：选择 `seed-001`、`seed-006`、`seed-009`，固定交替臂顺序，并用机器可检查的门槛约束角色、Fixture、执行器配置和隔离工作区。三个合成 Fixture 及其 executor-excluded oracle 已创建，workspace digest 已冻结，基础自检已通过；`fixtures_ready` 因此为 `true`。仓库外隔离工作区准备器也已实现，可拒绝覆盖并生成同源双臂副本及可验证收据，但它不替代执行器沙箱。新增 Executor Profile 契约会精确核对未决字段和冻结摘要，统一 preflight 会合并契约、四角色互斥、Profile 与 workspace-set 证据。四个角色仍未分配、Profile 仍缺六项真实决策、本次 Wave 的运行副本仍未生成，所以 Wave 明确保持 `blocked`，所有案例仍未运行。

随后完成测量契约加固：Case Schema 从 `0.1.0` 升级到 `0.2.0`，10 个未运行种子案例完成无数据迁移；运行记录新增 Executor Profile、模型/推理设置、Workspace Set 收据摘要、工作区结果 revision、返工和分段耗时字段。新增 Acceptance Result Schema `0.1.0`，只允许 `consensus`、`needs_adjudication`、`adjudicated` 三态，并由验证器根据 blocking Criteria、Material Re-specification、Safety Violation 与可用性推导 First-pass Delivery Success。当前仍为 0 条运行和 0 条验收结果，不构成效果数据。

下一轮把 Prompt Package v0 的 Markdown 语义落成 `schemas/prompt-package-v0.yaml` 和依赖无关的只读校验器。它交叉检查稳定 ID、事实/Evidence/Assumption 引用、六个 Review Lenses、风险与 Approval Point 覆盖，以及 `approved` / `required` / `rejected` / `not_applicable` 到 Handoff 允许/禁止动作的映射。合成测试夹具不进入校准数据；该能力只使未来 Package 可机器验收，不代表已经生成真实 Package 或解除 Wave 启动门禁。

本轮继续把 Clarification Policy 落成 `schemas/clarification-session-v0.yaml` 和依赖无关的只读校验器。它检查不可变 Intake 摘要、完整九维 gap map、问题优先级、1–3 问连续轮次、默认三轮限制、五态 Compile Gate，以及 Session 到 Prompt Package 的原始 Intent、问答、假设、未知项、决策与高风险 Approval Point lineage。配套 Session 与 Package 仍是合成测试夹具；没有代替用户回答、生成真实 Package、执行模型调用或产生产品效果数据。

下一轮补齐了 Clarification 的用户呈现切片：`docs/product/clarification-copy-v0.md` 固定五态标题、信息层级、追问格式、隐私提示和禁止泄漏字段，`scripts/render_clarification_copy.rb` 仅对已通过校验的 Session 生成 stdout Markdown。动态内容会折叠为单行并转义 HTML/Markdown；Renderer 不显示 raw Intent、保存的回答、内部优先级、source refs 或 decision maker ref，也不生成问题、推进状态或触发模型/网络。该能力改善可测的交互一致性，但仍不是实际用户验证或产品效果数据。

本轮在用户文案之后增加 Answer Receipt 信任边界：`schemas/clarification-answer-receipt-v0.yaml` 逐字保存 1–3 项原答，并绑定 Session ID、raw Intent 摘要、当前状态、连续轮次、问题摘要、回答摘要和数据声明；`scripts/preview_clarification_answers.rb` 只读检查 Receipt 是否适用于当前 `gap_scan` / `clarifying` 问题，并输出不回显原答的确认文案。它拒绝 intake/ready/blocked、错序或重复响应、摘要漂移、时间回退和数据分类降级；不会归一化、写回 Session、推导授权、调用模型或产生效果数据。

下一轮补上回答归一化到候选状态之间的显式审阅层：`schemas/clarification-revision-proposal-v0.yaml` 绑定原 Session、Answer Receipt 和连续轮次，声明问题结论、gap/知识项 delta、目标状态与 Compile Gate；`scripts/preview_clarification_revision.rb` 只在内存应用 delta，再调用完整 Clarification Session 校验器复验候选状态，并输出“确认 / 修改 / 拒绝”文案。六种允许的状态转换、回答类型到 outcome 的映射、无关知识项不可删除、既有高风险项原样保留、原答与内部标识不泄漏、CLI 零写入均有合成测试覆盖。该 Proposal 不是用户确认、Session revision 或风险授权，仍未产生真实用户数据、模型结果或商业效果证据。

本轮闭合用户确认到新 revision 的最小持久化链路：`schemas/clarification-confirmation-receipt-v0.yaml` 用三个输入文件的字节级 SHA-256 固定用户看到的 Session、Answer Receipt 与 Proposal，并把 `confirmed`、`modify_requested`、`rejected` 与 revision 创建权限做成可校验状态组合。`scripts/preview_clarification_confirmation.rb` 输出不回显确认原文和内部 lineage 的三态文案；`scripts/create_clarification_revision.rb` 只接受明确 confirmed Receipt，在全部校验完成后以 `0600` 权限创建不存在的新 Session 路径，并记录四份工件 lineage。输入漂移、时间/数据分类降级、非法选择组合、既有输出、缺失目录、Markdown 泄漏、确定性输出和零写入路径均由合成测试覆盖。该本地创建权限不扩展为外部写入或高风险授权，也没有生成真实用户确认或产品效果数据。

下一轮把创建时校验升级为可独立重放的持久化审计：`scripts/verify_clarification_revision_lineage.rb` 读取 Source Session、Answer Receipt、Revision Proposal、Confirmation Receipt 和 persisted revision，复用 Creator 的无写入 seam 确定性重建期望内容，再独立运行 Session 校验并逐字段比较 revision metadata 与全部业务内容。三种候选状态、非法持久化状态、四来源逐一漂移、lineage 摘要/原答/归一化结论/高风险边界篡改、YAML 等价排版和五文件零写入均有合成测试。成功文案只报告绑定、确认、重建和当前状态，不泄漏路径、摘要、内部 ID 或原答；通过只证明来源链完整，不是事实、授权、Prompt Package 或商业效果证据。

下一轮把 ready revision 到 Prompt Package 之间增加显式编译审阅层：`schemas/prompt-package-compilation-proposal-v0.yaml` 绑定 persisted Session revision 与候选 Package 的 ID、revision number、候选 Handoff 状态和字节摘要，并把创建、Handoff 与高风险授权固定为 false；`scripts/preview_prompt_package_compilation.rb` 重跑 Session/Package 各自校验和跨工件 lineage，再只展示范围、推荐方案、取舍、blocking 验收、未知项、审批边界、候选质量门和确认/修改/拒绝选项。ready/not-ready 候选、非 ready 或无 revision Session、双来源漂移、lineage 变化、时间/数据降级、越权声明、Markdown 泄漏和三文件零写入均有合成测试。该预演不保存选择、不创建最终 Package、不 Handoff，也未产生真实用户或效果数据；下一边界是独立保存 Compilation Confirmation Receipt。

下一轮把编译选择保存为独立 Confirmation Receipt：`schemas/prompt-package-compilation-confirmation-receipt-v0.yaml` 用三份来源文件摘要绑定 persisted Session revision、候选 Package 和 Compilation Proposal，并把确认、修改、拒绝与候选 Handoff 状态组合成可校验的创建权限表；`scripts/preview_prompt_package_compilation_confirmation.rb` 重跑完整 Proposal 预演，再校验选择、原文摘要、时间和数据策略，输出四种互斥结果文案。只有 confirmed + Handoff-ready 允许未来本地 creator 继续；confirmed + not-ready 只记录理解一致，修改和拒绝均阻断。三来源漂移、非法授权组合、数据降级、原文篡改、Markdown 泄漏和四文件零写入均有合成测试。该 Receipt 不创建最终 Package、不授权 Handoff、不改变 Approval Point，也未产生真实用户或效果数据；下一边界是 confirmed-only、no-overwrite 的最终 Package 创建与独立 lineage replay。

下一轮实现 confirmed-only 最终 Package Creator：Prompt Package Schema 增加可选 `compilation` lineage，现有候选保持兼容；`scripts/create_prompt_package.rb` 重跑 Session revision、候选 Package、Compilation Proposal 与 Confirmation Receipt 的完整链路，只允许 confirmed + Handoff-ready + creation-authorized，并在最终 Package 与 Session→Package lineage 复验后，以 `0600` 权限排他创建新路径。候选业务内容、Approval Point 与 Handoff 动作逐字段不变，只新增四来源摘要、确认时间和 false 授权推断。状态矩阵、来源漂移、确定性、拒绝覆盖、写入失败清理、Markdown 安全和信息不泄漏均有合成测试；创建不执行 Handoff，也不是效果证据。下一边界是 persisted Package 的独立 lineage replay verifier。

下一轮实现 persisted Prompt Package 的独立 lineage replay：`scripts/verify_prompt_package_lineage.rb` 读取 Session revision、候选 Package、Compilation Proposal、Confirmation Receipt 与 persisted final Package，复用 Creator 的无写入 seam 确定性重建期望内容，再独立运行 Package 与 Session→Package 校验，并分别逐字段比较 `compilation` metadata 和全部业务内容。四来源逐一漂移、metadata 身份/摘要篡改、Recommendation/Approval/Handoff 边界篡改、缺失 metadata、非法授权推断、畸形/等价 YAML、五文件零写入、CLI 与安全文案均有合成测试覆盖。验证通过只证明来源链完整并允许进入受控 Handoff 决策，不执行或授权 Handoff，也不是事实正确或产品效果证据；下一边界是显式 Handoff Proposal 与授权语义。

下一轮实现显式 Handoff Proposal：`schemas/handoff-proposal-v0.yaml` 把一个 pending、零授权提案绑定到 lineage-verified、`handoff.ready: true` 的精确最终 Package 字节摘要，并保持 recipient、时间与最高输入数据分类不降级；`scripts/preview_handoff_proposal.rb` 每次先重放 Session revision、候选 Package、Compilation Proposal、Confirmation Receipt 与最终 Package 的完整五文件 lineage，再校验第六份 Proposal。用户文案只展示交接对象、in-scope、允许/禁止动作、未决项、停止条件、Approval Point 和确认/修改/拒绝选项，动态内容经 Markdown 安全层处理，路径、摘要、内部 ID、原始 Intent、原答与 Evidence 来源不泄漏。来源/最终字节/绑定漂移、未就绪、越权状态、时间/数据降级、畸形输入和六文件零写入均有合成测试覆盖。该 Proposal 不保存选择、不授权 Handoff、外部效果或高风险动作，也不执行交接；下一边界是独立 Handoff Confirmation Receipt 和明确授权语义。

下一轮实现独立 Handoff Confirmation Receipt：`schemas/handoff-confirmation-receipt-v0.yaml` 用六份来源文件摘要、Package/Proposal ID、ready/recipient/pending 状态和用户原文摘要固定用户针对哪一份精确 Handoff Proposal 作出选择；`scripts/preview_handoff_confirmation.rb` 重跑完整六文件 Proposal 链，再校验确认、修改、拒绝与 `handoff_authorized` 的三态矩阵、时间、最高数据分类和 Receipt 自身的个人数据声明。只有 confirmed 必须为 true，修改和拒绝必须为 false；`external_effects_authorized`、`high_risk_authorization_inferred` 和 secrets 始终为 false，个人数据不得标为 public。六来源漂移、声明摘要/身份漂移、越权组合、原文摘要、时间/数据降级、个人数据、Markdown 泄漏、畸形输入与七文件零写入均有合成测试覆盖。confirmed 文案明确“授权成立但尚未交接”，并重申禁止动作、停止条件和 Approval Points；本轮没有调用 Agent、模型、网络或外部服务，也没有生成真实用户确认或效果数据。由于运行时与交接渠道仍未选定，下一边界建议为 confirmed-only、no-overwrite、`0600` 的本地 Handoff Envelope Creator：确定性封装精确 Package 与授权 lineage，仍不启动执行器；随后再实现独立 Envelope lineage verifier。真正 dispatch 必须等渠道、副作用和额外授权策略确定后再做。

下一轮实现 confirmed-only 本地 Handoff Envelope Creator：`schemas/handoff-envelope-v0.yaml` 定义 `prepared` 外壳、内嵌最终 Prompt Package、七文件摘要、数据声明和不变的权限边界；`scripts/create_handoff_envelope.rb` 重跑 Session revision 至 Handoff Confirmation Receipt 的完整链，只接受 confirmed + handoff-authorized，在所有校验完成后以 `0600` 权限排他创建新路径。ID 与时间从 Receipt 确定性派生，同一输入输出字节一致；修改/拒绝、来源漂移、已有路径与写入失败均零产物。Schema 外壳校验与完整 Prompt Package Validator 组合，避免复制大 Schema。用户文案固定“已创建，尚未交接”，展示准备状态、接收者、禁止动作、停止条件与 Approval Points，但不泄漏路径、摘要、ID、原始内容或确认原文。该 Envelope 没有启动 Agent、模型、网络、进程、通知或外部服务，不是交付/接收/执行记录，也没有产生真实用户或效果数据；下一边界是独立 Envelope lineage replay verifier，真正 adapter 仍后置。

下一轮实现 persisted Handoff Envelope 的独立 lineage replay：`scripts/verify_handoff_envelope_lineage.rb` 读取七份来源与 persisted Envelope，复用 Creator 的无写入 seam 确定性重建期望内容，再独立运行 Envelope Schema 与完整 Prompt Package Validator，并分别逐字段比较外壳 metadata、authorization metadata 和全部内嵌 Package 业务内容。七来源逐一漂移、七摘要与稳定 ID 篡改、prepared/权限越权、确认数据声明、Recommendation/Approval/Handoff 边界篡改、缺失/标量/畸形/等价 YAML、八文件零写入、CLI 与安全文案均有合成测试覆盖。成功文案明确“来源链已验证，仍未交接”，不泄漏路径、摘要、ID 或源内容；验证不选择或调用 Adapter、不启动执行器，也没有产生真实用户、交付或效果数据。下一边界是 provider-neutral Adapter Capability Profile 与零副作用选择 Proposal，真正 dispatch 仍后置到渠道选择和独立副作用授权之后。

下一轮实现 provider-neutral Adapter Capability Profile 与零副作用 Adapter Selection Proposal：`schemas/handoff-adapter-profile-v0.yaml` 定义 reviewed 候选的交付/回执/幂等/重试、数据/成本政策、七类副作用和逐项授权要求；`schemas/handoff-adapter-selection-proposal-v0.yaml` 把 exact verified Envelope 与 exact reviewed Profile 绑定到 pending、未选择、未 dispatch、零外部效果/高风险授权状态。`scripts/preview_handoff_adapter_selection.rb` 先重跑完整八文件 Envelope lineage，再校验 Profile 内部一致性、双文件摘要/身份/时间/数据分类，并生成不泄漏来源的十文件三选一文案。20 个聚焦测试覆盖七来源漂移、Envelope/Profile 字节漂移、Profile 状态/审查时间、五项 Proposal 越权状态、合法 bounded retry/cost 档案、回执/幂等/重试/成本/副作用授权矛盾、数据降级、compatibility unknown、畸形输入、Markdown 安全和 CLI 零写入。探索发现 Envelope 的个人数据/密钥声明不覆盖完整内嵌 Package，因此 Proposal 不能声称兼容；两项固定 unknown，真实 dispatch 前必须独立 payload review/attestation。下一边界是 Adapter Selection Confirmation Receipt；confirmed 也只记录所选 Profile，不允许 dispatch 或继承任何副作用授权。

下一轮实现独立 Adapter Selection Confirmation Receipt：`schemas/handoff-adapter-selection-confirmation-receipt-v0.yaml` 用全部十份先行文件的字节级 SHA-256、Envelope/Profile/Proposal 身份和用户原文摘要固定精确选择，并把 confirmed/modify_requested/rejected 与 adapter_selected 组合写成可校验状态表。`scripts/preview_handoff_adapter_selection_confirmation.rb` 每次重跑完整十文件 Selection Proposal 链，复用同次读取的摘要校验 Receipt，再检查时间、数据分类和个人数据/密钥边界。21 个聚焦测试覆盖三态、非法选择矩阵、全部十来源漂移、每个声明摘要、身份/原文/时间/数据篡改、越权 dispatch/外部效果/高风险/副作用授权、Markdown 安全与十一文件零写入。confirmed 只表示选中已审查 Profile，三态均保持未 dispatch、零效果授权，个人数据与密钥兼容性继续为 unknown；本轮没有实现或调用 Adapter、Agent、网络或外部系统，也没有生成真实用户确认或效果数据。下一边界是 provider-neutral Handoff Payload Data Attestation：覆盖完整 Package 内容的个人数据、密钥和目的适配证据；此后仍需对 Profile 中每个 `true` 副作用单独授权，才能考虑 dispatch。

下一轮实现 provider-neutral Handoff Payload Data Attestation：`schemas/handoff-payload-data-attestation-v0.yaml` 把完整 Envelope payload 的已完成审核声明绑定到 confirmed Adapter Selection 的全部十一份精确文件，区分 manual/automated/hybrid provenance，且只保存受控个人数据/密钥类别而不保存原始命中片段。`scripts/preview_handoff_payload_data_attestation.rb` 重放十一文件链，再由 Attestation 数据分类、Payload 事实与所选 Profile 的分类上限/个人数据/密钥策略派生分项和总体兼容性。兼容文案明确“审核通过，仍未授权 dispatch”；不兼容文案明确阻断且不泄漏类别或命中值。26 个聚焦测试覆盖分类/个人数据/密钥兼容与阻断矩阵、三种审核方式、十一来源逐一漂移、摘要/身份/状态/策略绑定、类别存在性、时间/分类、零 dispatch/effect/high-risk authorization、Markdown 安全与十二文件零写入。预演器不运行 Scanner、模型、Adapter、网络或外部系统，Fixture 不是真实审核证据，且 Profile v0 没有 retention/export/purpose 策略，不得声称这些维度已通过。下一边界是 pending、零授权 Adapter Effect Authorization Proposal；此后仍需独立选择回执、Adapter 实现契约与 dispatch 确认。

下一轮实现 provider-neutral Adapter Effect Authorization Proposal：`schemas/handoff-adapter-effect-authorization-proposal-v0.yaml` 把 pending、零授权披露绑定到 compatible Payload Data Attestation 的完整十二文件链；`scripts/preview_handoff_adapter_effect_authorization.rb` 先重放完整数据审核，再要求 requested effect 集合与所选 Profile 的全部 true effects 完全一致，镜像费用/生产数据披露，并固定 retention/export/purpose 为未核验。23 个聚焦测试覆盖单一、零和全部 effects、缺增项、不兼容审核、十二来源逐一漂移、每项声明摘要、身份/状态、费用/生产数据、越权转换、时间/分类、数据最小化、Markdown 安全、精确 Proposal 字节和十三文件零写入。Proposal 不保存选择、授予 effect、实现或调用 Adapter，也不 dispatch；下一边界是独立 Effect Authorization Confirmation Receipt，真实 Adapter 证明和 dispatch 确认继续后置。

下一轮实现 Adapter Effect Authorization Confirmation Receipt：`schemas/handoff-adapter-effect-authorization-confirmation-receipt-v0.yaml` 用十四文件契约绑定 exact Effect Proposal、用户原文摘要与具名 grant 状态机；`scripts/preview_handoff_adapter_effect_authorization_confirmation.rb` 重放完整十三文件链，要求 confirmed 授予全部且仅 requested effects，modify/reject 为空，并由选择派生费用与生产数据授权标志。28 个聚焦测试覆盖三种合法选择、全部非法转换、零/全部 effects、部分/额外 grants、费用上限、实现/contract-test/dispatch 门禁、十三来源漂移、摘要/身份/状态、原文/时间/数据、Markdown 安全与十四文件零写入。具名 effect consent 始终不可执行且 false dispatch；下一边界是 provider-neutral Adapter Implementation Attestation，真实凭据、健康检查和 dispatch 继续后置。

# Prompt Package v0 质量契约

- Status: Experimental
- Version: `0.1.0`
- Owner: PMind Validation Sprint
- Applies to: 模糊软件产品 Intent 到编码型 Downstream Executor 的 Handoff

## 目的

Prompt Package 是 PMind 的结构化交接产物，不是经过润色的一段提示词。它必须让不了解澄清过程的 Downstream Executor 能够理解目标、边界、证据、风险和验收方式，并且不需要猜测关键产品决策。

本契约用于人工 Concierge 验证。它定义语义，不绑定 Codex、模型供应商或应用技术栈。

对应的机器可读结构位于 `schemas/prompt-package-v0.yaml`，只读校验入口为 `scripts/validate_prompt_package.rb`。Markdown 定义产品语义，Schema 和业务校验器负责拒绝结构、引用、Review Lens、Approval Point 与 Handoff 状态之间的矛盾；校验通过不替代事实核验或下游 Eval。

若 Package 来自结构化 Clarification Session，还应运行 `ruby scripts/validate_clarification_session.rb SESSION --prompt-package PACKAGE`。该交叉校验要求逐字保留原始 Intent、用户问题与回答、假设、未知项、决策和高风险动作；它不允许编译器静默删除不利信息或伪造会话中不存在的决定。

对 persisted ready Session revision 形成候选 Package 后，还应按 [Prompt Package Compilation Proposal v0](prompt-package-compilation-proposal-v0.md) 绑定两个精确文件并展示确认文案。候选 `handoff.ready: true`、结构校验通过或 Proposal 预演成功都不等于用户已确认、最终 Package 已创建或 Handoff 已授权。

## 规范用语

- **必须**：缺失即不能通过 Quality Gate。
- **应该**：通常需要；省略时必须记录理由。
- **可以**：按任务需要提供。
- `unknown` 表示目前没有答案；`assumption` 表示为了继续而采用、但尚未证实的命题；两者不得写成 `fact`。

## 设计不变量

1. `raw_intent` 必须逐字保留用户原始输入，不允许用优化后的表述覆盖。
2. 事实、Evidence、推断、假设、未知项和决策必须可区分。
3. 外部事实必须指向可追溯的 Evidence；模型记忆不能单独成为 Evidence。
4. 高风险、外部写入、敏感数据、费用和不可逆动作必须关联 Approval Point。
5. 验收标准必须描述可观察结果，不得只写“体验良好”“代码优雅”等主观目标。
6. Handoff 默认只传递 Package，不授权 Downstream Executor 执行外部写入。
7. Package 不保存隐藏思维链；只保存用户答案、简洁决策理由、来源和可审计结论。

## 顶层结构

| 字段 | 必需 | 内容 |
| --- | --- | --- |
| `schema_version` | 是 | 固定为 `0.1.0` |
| `package_id` | 是 | Package 唯一标识，例如 `pkg-20260821-001` |
| `created_at` | 是 | 带时区的 ISO 8601 时间 |
| `language` | 是 | 用户交互语言；v0 默认为 `zh-CN` |
| `intent` | 是 | 原始 Intent、问题陈述和预期结果 |
| `context` | 是 | 用户、场景、现状和业务价值 |
| `scope` | 是 | 范围内、范围外和延期事项 |
| `constraints` | 是 | 产品、技术、数据、合规、时间和预算约束 |
| `knowledge` | 是 | 事实、Evidence、假设、未知项和决策 |
| `clarifications` | 是 | 已提出问题和用户确认结果；可以为空数组 |
| `review_findings` | 是 | 多视角审查结果 |
| `recommendation` | 是 | 建议方案、替代方案和取舍 |
| `execution_contract` | 是 | 下游输入、指令、输出和错误契约 |
| `acceptance_criteria` | 是 | 可观察且可判定的验收标准 |
| `risks` | 是 | 风险、影响、概率和缓解；可以为空数组 |
| `approval_points` | 是 | 需要人类明确授权的动作；可以为空数组 |
| `eval_plan` | 是 | Quality Gate 和下游结果的验证方法 |
| `handoff` | 是 | 交接对象、允许/禁止动作和未决事项 |

## 字段契约

### `intent`

- `raw_intent`：用户原文。
- `problem_statement`：经确认的问题，不得扩大原始目标。
- `desired_outcome`：业务或用户结果，而不是预设实现。
- `task_type`：`product_exploration`、`feature_definition`、`competitor_research`、`technical_selection` 或 `coding_handoff`。

### `context`

- `target_users`：具体用户角色及其需要。
- `scenarios`：触发条件、主要路径和使用环境。
- `current_state`：已有产品、流程、代码或数据状态。
- `business_value`：预期产生的价值及其观察方式。

没有上下文时必须在 `knowledge.unknowns` 记录缺口，不能生成虚构背景。

### `scope`

- `in_scope`：本次 Handoff 必须完成的结果。
- `out_of_scope`：明确排除的结果。
- `deferred`：有价值但推迟的事项及推迟原因。

### `constraints`

六类约束均必须存在：`product`、`technical`、`data`、`compliance`、`delivery`、`budget`。未知值用状态表示，不使用空泛占位文本。

每项约束包含：

- `id`；
- `statement`；
- `status`：`confirmed`、`assumed`、`unknown` 或 `not_applicable`；
- `source`：用户、Evidence ID 或决策 ID。

### `knowledge`

- `facts`：已由用户或 Evidence 支持的事实。
- `evidence`：来源记录，至少包含 `evidence_id`、URL/仓库路径、检索日期、版本或 commit（适用时）、许可证（适用时）、trust status 和实际用途。
- `assumptions`：为继续工作采用的可证伪命题，包含失效影响和验证方法。
- `unknowns`：尚无答案的问题，包含是否阻塞交付。
- `decisions`：已选择方案、决策者、理由、替代方案和日期。

### `clarifications`

每条记录包含 `question_id`、gap dimension、问题、用户答案、结果状态和影响的 Package 字段。只记录简洁理由，不保存模型隐藏思维过程。

### `review_findings`

每项使用 [Review Lenses v0](review-lenses-v0.md) 的统一输出：lens、verdict、finding、证据/假设引用、受影响字段和建议修改。任何未解决的 `block` 都会阻止 Handoff。

### `recommendation`

- `selected_option`：建议方案。
- `why`：与目标、Evidence 和约束的关系。
- `alternatives`：至少记录认真考虑过的替代方案；若不存在，说明原因。
- `tradeoffs`：获得什么、放弃什么。

### `execution_contract`

- `downstream_executor`：目标执行器与已知版本。
- `instructions`：要完成的工作和执行顺序；不得包含未经授权的外部动作。
- `inputs`：输入名称、类型、来源和敏感级别。
- `outputs`：预期文件、数据或可观察行为。
- `error_contract`：缺失输入、冲突约束、工具不可用和部分完成时的报告方式。
- `allowed_tools` / `forbidden_tools`：工具和权限边界。
- `references`：执行时允许读取的仓库文件或已审查 Reference。

### `acceptance_criteria`

每条标准必须包含：

- 稳定 `criterion_id`；
- 可观察的 `statement`；
- `verification_method`；
- `blocking` 布尔值；
- 验收负责人；
- 适用时的输入、期望结果和边界条件。

### `risks` 与 `approval_points`

风险包含 `risk_id`、类别、触发条件、影响、可能性、缓解和残余风险。Approval Point 包含 `approval_id`、对应风险/动作、授权人、授权范围和状态。v0 的有效状态为 `required`、`approved`、`rejected`、`not_applicable`。

机器契约按以下状态映射执行硬校验：

- `approved`：必须记录 `approver_ref`，动作只出现在 `handoff.authorized_actions`；
- `required`：动作仍未获授权，只能出现在 `handoff.prohibited_actions`；
- `rejected`：必须记录 `approver_ref`，动作继续保留在禁止列表；
- `not_applicable`：动作不出现在授权或禁止列表，但不能借此移除默认高风险动作。

同一动作不能拥有多个 Approval Point，也不能同时处于允许和禁止列表。标记 `requires_approval: true` 的风险必须被一个非 `not_applicable` Approval Point 覆盖。

动作以稳定的 `snake_case` key 在 Approval Point 与 Handoff 列表间关联；人员/角色只使用不含空白与个人信息的 opaque ref，不把姓名、邮箱或密钥写入 Package。

### `eval_plan`

- Package 结构检查；
- Evidence 与引用检查；
- 风险和 Approval Point 检查；
- 下游 Acceptance Criteria；
- First-pass Delivery Success 评分；
- 需要人工判断的项目与盲评方式。

### `handoff`

- `ready`：所有 Quality Gate 是否已通过；
- `recipient`：Downstream Executor；
- `authorized_actions`：已授权范围；
- `prohibited_actions`：默认包含提交、推送、部署、发送消息和修改外部服务，除非存在已批准 Approval Point；
- `open_items`：不阻塞但需告知执行器的未知项；
- `stop_conditions`：执行器必须停止并返回用户的条件。

## Quality Gate

Package 只有同时满足以下条件才能标记 `handoff.ready: true`：

1. 所有必需字段存在且语义完整。
2. 不存在未标记的事实、假设或未知项。
3. 所有外部事实均有 Evidence 引用。
4. 不存在未解决的 `block` 审查结论。
5. 所有 blocking Acceptance Criteria 都有验证方法。
6. 所有高风险动作都有 Approval Point；未获授权的动作被列入禁止范围。
7. Downstream Executor、输入、输出、错误处理和停止条件明确。

六个 Review Lens 都必须至少有一条结构化结论。存在 blocking unknown 或任一 `block` 时，校验器会拒绝 `handoff.ready: true`，但允许以 `ready: false` 保存诚实的未就绪 Package。

除非存在已批准且限定范围的 Approval Point，以下动作必须保留在 `handoff.prohibited_actions`：`commit`、`push`、`deploy`、`send_message`、`external_service_write`。

Package 可以带着非阻塞未知项交接，但必须在 `handoff.open_items` 中完整披露。

## 版本与变更

- v0 案例固定使用 `0.1.0`；实验期间只能新增非必需字段或修正文案歧义。
- 删除/重命名字段、改变状态含义或改变成功判定属于不兼容变更，必须提升主/次版本并重新校准案例。
- 每次实验记录实际 Schema 版本；不得用新契约覆盖旧运行结果。

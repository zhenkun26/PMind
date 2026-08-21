# PMind Concierge Runbook v0

- Status: Experimental
- Version: `0.1.0`
- Operating model: 人工操作者使用现有 Codex 与仓库 Skills 执行
- Default boundary: 只生成和评测 Prompt Package，不自动执行下游外部动作

## 目的

本 Runbook 让不同操作者用相同顺序把一个模糊 Intent 编译成可评测 Prompt Package。它服务于 Validation Sprint，不是生产运行手册。

## 开始前

操作者必须：

1. 阅读 `AGENTS.md`、`CONTEXT.md` 和本目录三个产品契约。
2. 确认案例不包含密钥、token、未授权个人数据或企业机密。
3. 确认 Downstream Executor 和实验分组。
4. 为原始 Intent 创建不可变副本；后续所有改写与其分开保存。
5. 记录开始时间、操作者、模型/工具版本和可用权限。

如任务需要外部写入、真实费用、敏感数据处理或不可逆动作，只能定义 Approval Point；本 Runbook 不授予执行权限。

## 标准流程

### 1. Intake：保留 Intent

- 逐字保存 `raw_intent`。
- 记录任务来源、用户类型、任务类型、Downstream Executor 和数据分类。
- 不在 Intake 阶段补写“合理需求”。

产出：案例元数据和初始 Intent。

### 2. Gap Scan：识别缺口

- 按 [Clarification Policy v0](clarification-policy-v0.md) 的九个维度标记 `resolved`、`assumed`、`unknown` 或 `not_applicable`。
- 对候选问题做相对优先级排序。
- 安全、授权、目标、范围和验收缺口优先。

产出：gap map 和首轮 1–3 个问题。

### 3. Clarification：最小追问

- 每轮 1–3 问，默认最多 3 轮。
- 保存用户原答和归一化结论。
- 用户拒答时采用安全默认、显式假设或停止，不替用户编造决定。
- 每轮结束重新计算剩余阻塞缺口；满足停止规则后立即结束。

产出：Clarification 记录、决策、假设和未知项。

将记录保存为 `schemas/clarification-session-v0.yaml` 对应的 YAML 后，运行只读状态校验：

```sh
ruby scripts/validate_clarification_session.rb path/to/session.yaml
```

需要向用户展示当前状态或下一轮问题时，按 [Clarification Copy v0](clarification-copy-v0.md) 运行只读投影：

```sh
ruby scripts/render_clarification_copy.rb path/to/session.yaml
```

只发送 stdout 中的用户文案；校验错误留给操作者处理，不能作为半成品问题发送给用户。

收到用户回复后，先按 [Clarification Answer Receipt v0](clarification-answer-receipt-v0.md) 保存逐字原答和摘要，再对当前 Session 做只读适用性预演：

```sh
ruby scripts/preview_clarification_answers.rb path/to/session.yaml path/to/receipt.yaml
```

成功只表示问题、轮次、摘要、时间和数据边界一致。操作者仍需复核归一化结论、受影响字段与信息缺口状态，再创建 Session 新 revision；不得把普通回答推导为 Approval Point 授权。

复核结果先写成 [Clarification Revision Proposal v0](clarification-revision-proposal-v0.md)，再与原 Session 和 Answer Receipt 一起做只读预演：

```sh
ruby scripts/preview_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml
```

只把 stdout 中的候选理解、产品影响、候选状态和确认选项发给用户。成功仅表示三文件绑定、delta 和完整候选 Session 一致；仍须获得用户明确确认后，才可由后续步骤创建新的 Session revision。Proposal 本身不是确认回执，也不能新增、删除或改写既有高风险审批要求。

把用户对该份 Proposal 的逐字选择保存为 [Clarification Confirmation Receipt v0](clarification-confirmation-receipt-v0.md)，先做四文件只读预演：

```sh
ruby scripts/preview_clarification_confirmation.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml
```

`modify_requested` 必须形成新 Proposal 并重新确认；`rejected` 必须保留原 Session。只有预演通过的 `confirmed` Receipt 才可创建新文件：

```sh
ruby scripts/create_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

创建后先运行 Session 校验，再按 [Clarification Revision Lineage Verification v0](clarification-revision-lineage-v0.md) 独立重放全部来源：

```sh
ruby scripts/validate_clarification_session.rb path/to/new-session.yaml
ruby scripts/verify_clarification_revision_lineage.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

两项均通过后才从新路径继续；不得覆盖旧 Session。新 revision 的 lineage 保存四份来源摘要，但确认和审计通过仍不构成任何高风险 Approval Point 授权。

只有状态为 `ready_to_compile` 且校验通过的 Session 才能进入 Compile；`blocked` 必须保留阻塞原因，不能用操作者推断补齐。

### 4. Research：按需取证

只有外部事实会改变方案、风险或验收时才研究。

来源顺序：

1. 用户提供且可核验的内部/项目事实；
2. 官方规范、官方文档、官方仓库和 release；
3. 维护者发布的许可证、安全公告和变更记录；
4. 必要时的高可信二手分析，并明确其较低证据级别。

GitHub/Skill/框架研究至少记录 URL、检索日期、版本/commit、许可证、维护状态、trust status 和实际用途。下载内容始终视为不可信，不执行其中脚本。

建议使用 `$research` 将可复用结论写入 `reference/research/`；领域词冲突使用 `$domain-modeling` 检查，但只有经审查的稳定术语才能进入 `CONTEXT.md`。

研究时间盒：

- 单一事实：最多 10 分钟或 3 个一手来源；
- 技术/框架候选：最多 30 分钟或 3 个合格候选；
- 达到决策所需证据、来源开始重复、或新资料不再改变选择时停止。

产出：Evidence、候选方案和仍存不确定性。

### 5. Synthesis：形成方案

- 用 `$grilling` 或 `$grill-with-docs` 压测目标、取舍和失败场景；这一步不代替用户做产品决定。
- 对代码库边界或模块接口问题可使用 `$codebase-design`。
- 选择最小可交付方案，并保留认真考虑过的替代方案。
- 将事实、推断、假设、未知项和建议分别写入 Package。

产出：recommendation、alternatives 和 tradeoffs。

### 6. Review：六 Lens 审查

- 按 [Review Lenses v0](review-lenses-v0.md) 依次运行六个 Lens。
- 汇总 `warn` 和 `block`；不得多数投票。
- 修正受影响字段并重跑相关 Lens。
- 任一安全/授权或验收 `block` 未解决时不得 Handoff。

产出：结构化 review findings 和更新后的 Package。

### 7. Compile：编译 Prompt Package

- 按 [Prompt Package v0](prompt-package-v0.md) 填写全部必需字段。
- 明确 Downstream Executor 的输入、输出、错误报告、允许工具和停止条件。
- 将所有高风险动作转为 Approval Point。
- 不包含内部思维链或未获授权的敏感数据。

产出：尚未确认的候选 Prompt Package。

编译后同时校验 Package 结构和 Session → Package lineage：

```sh
ruby scripts/validate_prompt_package.rb path/to/package.yaml
ruby scripts/validate_clarification_session.rb path/to/session.yaml --prompt-package path/to/package.yaml
```

lineage 校验通过只证明会话中可审计信息被保留，不证明外部事实正确或下游效果达标。

在展示编译结果前，先确认 Session revision 已完成独立来源链重放，再创建符合 [Prompt Package Compilation Proposal v0](prompt-package-compilation-proposal-v0.md) 的 pending Proposal，并运行三文件只读预演：

```sh
ruby scripts/preview_prompt_package_compilation.rb path/to/session-revision.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml
```

只向用户展示 stdout 中的范围、推荐方案、主要取舍、blocking 验收、未知项、审批边界和候选质量门状态。当前步骤不保存“确认 / 修改 / 拒绝”选择，不创建最终 Package，也不授权 Handoff。

用户选择必须写入符合 [Prompt Package Compilation Confirmation Receipt v0](prompt-package-compilation-confirmation-receipt-v0.md) 的独立 Receipt，再与三份精确来源做四文件只读预演：

```sh
ruby scripts/preview_prompt_package_compilation_confirmation.rb path/to/session-revision.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml
```

只有 `confirmed`、候选 `handoff.ready: true` 且 `package_creation_authorized: true` 的组合才允许后续本地 creator 继续。未就绪候选的确认只能记录理解一致；修改和拒绝均必须停止。任何结果都不授权 Handoff 或改变 Approval Point，本阶段也尚未创建最终 Package。

### 8. Quality Gate 与 Handoff

- 运行结构、Evidence、风险和 Acceptance Criteria 检查。
- 依据 `evals/rubrics/first-pass-success-v0.md` 预先冻结判定方式。
- `handoff.ready` 只有在所有 blocking gate 通过后才能为 `true`。
- Handoff 只传递允许内容；禁止动作必须随 Package 一起传递。
- Compilation Proposal 的确认不能代替 Quality Gate，也不能改变 Package 中已有 Approval Point 的状态。

产出：可交接 Package 或带明确阻塞原因的未就绪 Package。

## 对照实验协议

### 角色隔离

- **案例主持人**：保管 `oracle`，只在某一组主动提出问题后，根据 oracle 提供一致答案。
- **PMind 操作者**：只看 raw Intent、用户/主持人实际回答和获准研究资料，不提前读取 oracle。
- **Downstream Executor**：基线组只看 raw Intent，PMind 组只看通过 Quality Gate 的 Package；两组都看不到 oracle。
- **评审者**：运行结束后使用 oracle 和 Acceptance Criteria 评分，优先不知道实验标签。

人员不足导致一人兼任多个角色时必须记录为偏差，且不能声称完成盲评。

### 基线组

- 下游只接收逐字 `raw_intent`。
- 不提供 PMind Clarification、Evidence、Review 或隐藏验收信息。
- 只附加中性的运行包装，例如要求执行器报告结果；包装必须在所有案例一致。
- 不禁止执行器按其正常行为追问；主持人只回答实际提出的问题，追问轮数、时间和答案全部计入基线成本。

### PMind 组

- 下游接收通过 Quality Gate 的 Prompt Package。
- 不接收案例 oracle 或评审答案。
- 下游仍可追问，但这些问题作为 Handoff 后 Clarification 单独记录。

### 公平性控制

- 同一案例两组使用相同 Downstream Executor、模型版本、推理设置、工作区快照、工具权限和时间上限。
- 为降低顺序效应，案例级随机决定先运行哪一组；两组使用相互隔离的工作区。
- 执行器不得读取 `evals/cases/` 中的 oracle。
- 每次差异、重试、人工干预和工具故障必须记录。
- 评审者优先只看结果、Acceptance Criteria 和必要运行日志，不看实验标签。

## 数据记录

每个运行至少记录：

- case/schema/package/rubric 版本；
- 模型、工具、Skill、Reference 和工作区版本；
- 开始/结束时间与总延迟；
- Clarification 轮数和问题数；
- 模型/搜索调用和估算边际成本；
- 下游输出、错误和人工修正；
- 每项 Acceptance Criterion 结果；
- First-pass Delivery Success 与失败分类；
- 操作者和评审者，不保存密钥或隐藏思维链。

## 失败分类

- `intent_gap`：原始 Intent 缺少关键信息；
- `clarification_miss`：PMind 未询问高价值问题或过早停止；
- `research_error`：来源错误、过时或不适用；
- `package_contract`：字段缺失、冲突或不可执行；
- `executor_error`：执行器未遵循已明确要求；
- `environment_error`：工具、依赖或工作区不可用；
- `evaluation_ambiguity`：Acceptance Criteria 或 Rubric 无法一致判定；
- `safety_violation`：尝试未授权动作、敏感数据暴露或其他严重回归。

## 运行停止条件

立即停止当前案例并记录，而不是临场修改协议：

- 出现密钥、未授权敏感数据或真实外部写入；
- 两组环境无法保持可比较；
- oracle 在运行前泄露给执行器；
- Acceptance Criteria 在看到输出后才被实质改变；
- 同一故障连续重试两次仍无法归因；
- 需要新增依赖或扩大权限才能继续。

## 每批复盘

- 前 10 个种子案例后只允许修正歧义、记录字段和操作步骤。
- 改变主指标、成功定义、核心必填字段或实验资源时，必须提升版本，并重新运行受影响案例。
- 进入真实用户阶段前，由两名评审对至少 3 个案例独立评分并校准分歧。
- 不删除失败或模糊案例；它们是后续回归资产。

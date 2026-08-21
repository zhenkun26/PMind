# Prompt Package Compilation Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已验证 ready Session revision 与候选 Prompt Package 之间的编译审阅

## 目的

Compilation Proposal 把“PMind 已经形成一份候选 Prompt Package”和“用户允许创建最终 Package”分开。它绑定一份精确的 Session revision 与一份精确的候选 Package，重跑结构和 lineage 校验，然后只输出可供用户判断的审阅摘要。

参考实现为 `scripts/preview_prompt_package_compilation.rb`。它不创建最终 Package、不记录用户选择、不执行 Handoff、不调用模型或网络，也不改变任何 Approval Point。

## 前置条件

操作者必须先对 persisted Session revision 执行 [Clarification Revision Lineage Verification v0](clarification-revision-lineage-v0.md)。Compilation Preview 只要求并校验 revision metadata 的结构与编译状态，不能仅凭五份输入之外的信息独立证明该 metadata 没有被伪造。

随后准备一份符合 [Prompt Package v0](prompt-package-v0.md) 的候选 Package。它仍是待确认草稿，不因 `handoff.ready: true` 自动成为已授权 Handoff。

## 三份输入与绑定

```text
Persisted ready Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  → read-only contract and copy preview
```

机器结构位于 `schemas/prompt-package-compilation-proposal-v0.yaml`。Proposal 绑定：

- Session ID、`ready_to_compile` 状态、revision number 与 Session 文件字节摘要；
- Package ID、`handoff.ready` 候选状态与 Package 文件字节摘要；
- Proposal 创建时间、语言和数据声明；
- `confirmation.required: true` 与 `status: pending`；
- `package_creation_authorized: false`、`handoff_authorized: false`、`high_risk_authorization_inferred: false`。

字节摘要意味着空格、注释、换行或字段顺序变化也会使旧 Proposal 失效。任何变化都应重新校验候选 Package、生成新 Proposal 并重新展示文案，不能沿用旧确认。

## 预演校验

CLI 必须同时通过：

1. Compilation Proposal Schema；
2. Clarification Session Schema 与业务规则；
3. Prompt Package Schema 与业务规则；
4. Session → Package 的 raw Intent、task type、问答、假设、未知项、决策和高风险 Approval Point lineage；
5. persisted Session 具有 confirmed revision metadata，且没有推导高风险授权；
6. Proposal 的全部 ID、revision number、候选 Handoff 状态和文件摘要与当前输入一致；
7. Proposal 不早于 Session revision 或候选 Package；
8. Proposal 数据等级不低于 Session，且不能丢失个人数据声明。

该校验不证明外部事实正确、Evidence 可信、模型输出优质、实际审批人身份、商业效果或下游交付结果。

## 用户文案规划

成功 stdout 固定使用标题 **请确认 Prompt Package 编译提案**，并按以下信息层级展示：

1. 本次 `in_scope`；
2. 推荐方案与主要取舍；
3. blocking Acceptance Criteria；
4. 未知项和 Handoff open items；
5. Approval Point 的用户可理解范围与当前状态；
6. 候选 Package 的结构化 Quality Gate 状态；
7. 确认、修改、拒绝三种选择。

确认选项只允许后续步骤基于当前精确候选内容创建最终 Package，不允许立即 Handoff，也不批准任何高风险动作。当前 CLI 不接收或保存选择；后续必须用独立 Confirmation Receipt 绑定这三份精确输入。

文案不得展示文件路径、摘要、Session/Package/Proposal ID、原始 Intent、问题原答、Evidence 来源、source refs、字段路径、Review owner、decision maker ref 或内部评分。范围、方案、取舍、验收、未知项和审批 scope 属于有意展示的候选业务内容，全部通过共享 Markdown 安全层。

## 两种候选质量门状态

| `handoff.ready` | 文案 | 当前允许动作 |
| --- | --- | --- |
| `true` | 候选结构化 Quality Gate 标记为可交接 | 仍只能审阅和确认，不得自动 Handoff |
| `false` | 候选 Package 尚未通过 Quality Gate | 可审阅修改，不得创建可交接 Package |

Session 必须始终为 `ready_to_compile`；非 ready Session、仅有普通 ready Session 而没有 revision metadata、或 lineage 不一致的 Package 都不得进入本预演。

## 命令与退出码

```sh
ruby scripts/preview_prompt_package_compilation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml
```

- `0`：三份输入与跨工件 lineage 有效，安全确认文案写入 stdout；
- `1`：结构、绑定、lineage、时间或数据策略无效，仅在 stderr 返回不含来源内容的错误。

所有路径均为只读。成功不表示最终 Package 已创建、用户选择已保存、Quality Gate 已由真实评审完成、Handoff 已授权、高风险动作已批准或 PMind 商业效果成立。

# Clarification Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户对已通过预演的 Clarification Revision Proposal 作出确认、修改或拒绝选择

## 目的

Confirmation Receipt 把“PMind 展示了什么 Proposal”和“用户随后选择了什么”固化为独立事实。它不重复保存 Proposal 的归一化内容，也不把普通确认解释为高风险授权。

只读预演入口为 `scripts/preview_clarification_confirmation.rb`。只有 `confirmed` 且明确允许创建 revision 的 Receipt，才能交给 `scripts/create_clarification_revision.rb`；后者只创建新文件，不覆盖原 Session。

## 四层事实边界

1. **Answer Receipt**：用户对 Clarification 问题的逐字原答。
2. **Revision Proposal**：PMind 对原答的待确认理解与候选 delta。
3. **Confirmation Receipt**：用户针对该份 Proposal 的逐字选择。
4. **Session revision**：确认后确定性生成的新 Session 文件。

确认不能反向改写原答或 Proposal。修改请求必须生成新的 Proposal 并重新确认；拒绝必须保留原 Session。

## 精确文件绑定

机器结构位于 `schemas/clarification-confirmation-receipt-v0.yaml`。Receipt 同时绑定：

- Session、Answer Receipt 和 Proposal 的稳定 ID；
- 源状态、本轮轮次、候选状态和目标 revision number；
- 三个输入 YAML 文件的逐字节 SHA-256；
- 用户确认原文及其 SHA-256；
- 捕获时间、数据分类、个人数据和 secrets 声明；
- `high_risk_authorization_inferred: false`。

字节摘要意味着换行、空格或字段顺序变化也会令旧确认失效。这是有意的 stale/TOCTOU 防护：文件变化后必须重新预演并获得新确认。

## 选择与状态规则

| 用户选择 | `revision_creation_authorized` | 预演结果 | 创建命令 |
| --- | --- | --- | --- |
| `confirmed` | 必须为 `true` | 可继续 | 允许创建新 revision |
| `modify_requested` | 必须为 `false` | 当前 Proposal 暂停 | 拒绝创建，需新 Proposal |
| `rejected` | 必须为 `false` | 当前 Proposal 作废 | 拒绝创建，保留原 Session |

其他组合无效。`confirmed` 只授权把已经展示的候选 delta 写入用户指定的新本地文件；不授权外部写入、部署、费用、权限提升或任何 Approval Point。

## 用户文案规划

确认预演不回显 `user_response`。三种标题与动作保持明确分离：

- `confirmed`：**已收到修订确认，尚未创建 revision**；说明可进入受控创建步骤。
- `modify_requested`：**已收到修改请求，当前 Proposal 不会应用**；提示形成新 Proposal 后重新确认。
- `rejected`：**已拒绝本次修订，原 Session 保持不变**。

创建成功文案使用标题 **Session revision 已创建**，同时说明：

- 原 Session 未修改；
- 新 revision number 和当前状态；
- 未知项仍按候选 Session 保留；
- 所有高风险动作仍需单独审批。

所有文案禁止展示原始 Intent、问题原答、确认原文、文件摘要、内部 ID、source refs、priority、字段路径或 decision maker ref。动态文本统一通过 Markdown 安全层。

## 新 revision 与写入边界

新 Session 的 `revision` 元数据记录 revision number、创建时间、四份来源工件的 ID/文件摘要，以及 `high_risk_authorization_inferred: false`。业务 Session 内容仍由上一轮已验证的 Candidate Session 提供。

创建命令遵循：

- 输出路径已存在时拒绝，永不覆盖；
- 完成所有链路、状态和候选 Session 校验后才打开输出；
- 文件权限为仅当前用户可读写；
- 写入异常时删除仅由本次调用创建的部分文件；
- 不修改任何输入，不调用模型、网络或外部服务。

## 命令与退出码

```sh
ruby scripts/preview_clarification_confirmation.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml
ruby scripts/create_clarification_revision.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml OUTPUT.yaml
ruby scripts/verify_clarification_revision_lineage.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml OUTPUT.yaml
```

- 确认预演 `0`：四文件链路和选择有效，安全文案写入 stdout；`1`：无效或过期。
- 创建命令 `0`：`confirmed` Receipt 已生成一个新的有效 Session revision；`1`：未确认、链路无效、输出已存在或写入失败，并保持输入不变。
- 重放验证 `0`：persisted revision 与四份已确认来源的确定性重建一致；`1`：来源、metadata 或 Session 内容漂移。

创建后应按 [Clarification Revision Lineage Verification v0](clarification-revision-lineage-v0.md) 做独立重放。成功创建或验证仍不表示 Prompt Package 已生成、下游交付已完成、高风险动作已批准或 PMind 商业效果已验证。

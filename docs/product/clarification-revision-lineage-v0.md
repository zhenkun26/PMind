# Clarification Revision Lineage Verification v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已持久化 Clarification Session revision 的独立来源链重放审计

## 目的

创建时校验只能证明当时的输入和输出一致。Lineage Verification 允许后续操作者、审计流程或下游编译步骤重新提供五份文件，证明 persisted revision 仍能由同一组已确认来源确定性重建，并且没有发生内容或 lineage 篡改。

参考实现为 `scripts/verify_clarification_revision_lineage.rb`。它只读五份 YAML，不创建报告文件、不修改 revision、不调用模型、网络或外部服务。

## 五份输入

```text
Source Session
  + Answer Receipt
  + Revision Proposal
  + Confirmation Receipt
  → deterministic reconstruction
  ↔ Persisted Session revision
```

验证器执行：

1. 重跑 Answer Receipt、Revision Proposal 与 Confirmation Receipt 的完整绑定、时间、数据和状态校验；
2. 要求 Confirmation Receipt 为 `confirmed` 且允许本地 revision 创建；
3. 使用 Creator 的无写入构建 seam 重建期望 revision；
4. 独立校验 persisted revision 的 Session Schema 与业务不变量；
5. 逐字段核对 revision metadata；
6. 比较除 metadata 外的完整 Session 内容。

来源文件继续按字节 SHA-256 绑定。Persisted revision 本身按解析后的 YAML 结构比较，因此等价的缩进、注释、引号或字段排版变化不会造成失败；任何业务值、数组顺序、原答、状态、Compile Gate、知识项、风险或 lineage 值变化都会失败。

## 审计结果状态

| 输入状态 | 结果 | 后续动作 |
| --- | --- | --- |
| 五文件有效且内容可确定性重建 | `verified` | 按 revision 当前状态继续 |
| 任一来源摘要、ID、轮次或确认漂移 | `invalid` | 停止，恢复原始工件或重新确认 |
| Persisted revision 结构无效 | `invalid` | 停止，不得用于编译或追问 |
| Revision metadata 与来源不一致 | `invalid` | 视为 lineage 篡改或错误归档 |
| Session 内容与重建结果不一致 | `invalid` | 视为未确认变更，不得继续 |

验证器不修复失败，也不选择“最可信版本”。任何自动修复都会破坏审计证据，应由操作者保留原文件并形成新的受控 revision。

## 用户可见审计文案

成功时 stdout 使用标题 **Session revision 来源链已验证**，并按以下顺序展示：

1. 来源文件绑定、确认选择和确定性重建均匹配；
2. revision number 与当前 Session 状态；
3. 所有仍需单独审批的高风险动作；
4. 与当前状态匹配的下一步：继续澄清、进入 Prompt Package 编译准备或保留阻塞。

文案不得展示文件路径、摘要、内部 ID、原始 Intent、问题原答、确认原文、source refs、priority、字段路径或 decision maker ref。动态风险说明使用共享 Markdown 安全层。

失败只写入 stderr，供操作者诊断；失败信息同样不得回显原答或确认原文。

## 命令与退出码

```sh
ruby scripts/verify_clarification_revision_lineage.rb SOURCE_SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml REVISION.yaml
```

- `0`：五文件有效，persisted revision 与确定性重建逐字段一致，安全审计文案写入 stdout；
- `1`：任一输入不可读、链路无效、metadata 不匹配或 Session 内容漂移，仅在 stderr 返回错误。

验证通过只证明 revision 的可重放来源链完整；不证明用户身份、输入事实正确、Prompt Package 已生成、下游交付成功、高风险动作获批或 PMind 商业效果成立。

# Handoff Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 来源链已验证的最终 Prompt Package 进入 Handoff 授权前的只读提案

## 目的

Handoff Proposal 在“最终 Package 已验证”和“用户明确授权交接”之间增加独立决策边界。它让用户先看到交接对象、交付范围、允许与禁止动作、未决项、停止条件和 Approval Points，再选择确认、修改或拒绝。

Proposal 本身始终是 `pending` 且零授权：它不保存用户选择、不授权或执行 Handoff、不调用模型或网络、不修改外部系统，也不把普通确认推导为高风险授权。

参考实现为 `scripts/preview_handoff_proposal.rb`，机器契约为 `schemas/handoff-proposal-v0.yaml`。

## 六份只读输入

```text
Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  + Persisted final Prompt Package
  + Handoff Proposal
  → safe pending decision copy
```

预演器先对前五份文件运行完整 Prompt Package lineage replay，再使用同一次读取取得的最终 Package 原始字节计算 SHA-256。Proposal 必须精确匹配：

- 最终 Package ID 和文件字节摘要；
- `handoff.ready: true`；
- `handoff.recipient`；
- 不早于最终 Package `compilation.created_at` 的创建时间；
- 不低于 `execution_contract.inputs` 最高等级的数据分类；
- `pending`、`handoff_authorized: false`、`external_effects_authorized: false` 和 `high_risk_authorization_inferred: false`。

任何来源、最终 Package 或 Proposal 漂移都必须停止。修改 Package 的业务字段不能覆盖原链路；操作者须形成新的候选 Package、Compilation Proposal、Confirmation Receipt 和最终 Package。

## 状态与权限

| Proposal 状态 | 合法 | 作用 |
| --- | --- | --- |
| `pending` + 三项授权均为 `false` | 是 | 只展示三种选择 |
| 已确认、已拒绝或已请求修改 | 否 | 应由后续独立 Confirmation Receipt 表达 |
| Handoff、外部效果或高风险授权为 `true` | 否 | Proposal 不得携带或推导权限 |
| 最终 Package 未就绪或来源链失败 | 否 | 不得展示可确认的 Handoff Proposal |

## 用户可见文案

成功文案标题为 **Handoff 提案待确认，尚未交接**，依次展示：

1. 人类可读的交接对象；
2. `scope.in_scope`；
3. `handoff.authorized_actions` 与 `handoff.prohibited_actions`；
4. `handoff.open_items` 与 `handoff.stop_conditions`；
5. Approval Point scope 与当前状态；
6. 确认、请求修改、拒绝三种选择。

确认选项只表示“允许后续受控步骤记录 Handoff 决策”，当前预演不保存选择。选择必须写入独立的 [Handoff Confirmation Receipt v0](handoff-confirmation-receipt-v0.md)。请求修改须回到候选 Package 和新的编译确认链；拒绝保留已验证的最终 Package，但不得交接。

所有动态内容必须经过共享 Markdown 安全层。文案不得展示文件路径、摘要、Session/Package/Proposal/Confirmation ID、原始 Intent、Clarification 原答、Evidence 来源、source refs、Review owner、decision maker ref 或内部字段路径。

## 命令与退出码

```sh
ruby scripts/preview_handoff_proposal.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml
```

- `0`：前五文件 lineage 完整，最终 Package 可交接，Proposal 精确绑定且保持 pending 零授权；安全文案写入 stdout；
- `1`：任一文件不可读、来源链失败、绑定/时间/数据策略漂移、Package 未就绪或 Proposal 越权；错误写入 stderr。

成功只表示用户可以审阅 Handoff 提案，不证明用户身份、事实正确、Approval Point 已批准、Handoff 已授权或发生、下游交付成功或 PMind 商业效果成立。下一步必须用 Handoff Confirmation Receipt 保存并复验用户的明确选择。

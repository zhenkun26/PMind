# Handoff Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户对已通过预演的精确 Handoff Proposal 作出确认、修改或拒绝选择

## 目的

Handoff Confirmation Receipt 把“用户看到的是哪一份完整提案链”和“用户随后选择了什么”保存为独立事实。它允许 `confirmed` 明确授权未来受控步骤交接这一份精确 Prompt Package，但不执行 Handoff、不授权外部效果，也不改变任何 Approval Point。

只读入口为 `scripts/preview_handoff_confirmation.rb`，机器契约为 `schemas/handoff-confirmation-receipt-v0.yaml`。

## 七层事实边界

```text
Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  + Persisted final Prompt Package
  + Handoff Proposal
  + Handoff Confirmation Receipt
  → safe choice result
```

CLI 先完整重跑前六文件的 Handoff Proposal 预演，并取得每次实际读取的字节摘要，再校验第七份 Receipt。Receipt 绑定：

- Session revision、候选 Package、Compilation Proposal 与 Compilation Confirmation Receipt 的文件摘要；
- 最终 Package ID、文件摘要、`handoff.ready: true` 与 recipient；
- Handoff Proposal ID、文件摘要与 `pending` 状态；
- 用户选择原文及其 SHA-256；
- 捕获时间、数据分类、个人数据和 secrets 声明。

任一来源即使只改变注释、空格、换行或字段排版，旧 Receipt 都会失效。修改 Handoff 范围、接收者、动作边界或停止条件时，必须从新的候选 Package 和编译确认链开始。

## 选择与授权状态表

| `confirmation_decision` | `handoff_authorized` | 结果 |
| --- | --- | --- |
| `confirmed` | 必须为 `true` | 后续受控 Handoff 步骤可以继续 |
| `modify_requested` | 必须为 `false` | 当前授权未成立，重新形成完整 Package 与 Proposal 链 |
| `rejected` | 必须为 `false` | 当前 Handoff 终止，保留已验证最终 Package |

其他组合全部无效。所有状态都必须保持：

- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- `contains_secrets: false`。

Receipt 保存逐字用户选择，因此 `contains_personal_data: true` 时不得使用 `public` 数据分类。

`handoff_authorized: true` 的范围只有：未来受控步骤可以把 Receipt 绑定的精确 Package 交给已声明 recipient。它不授权提交、推送、部署、发消息、网络调用、外部服务写入、费用、生产数据访问、权限提升或 Package 中仍待 Approval Point 的动作。若实际交接渠道会产生外部效果，必须另行获得该效果的明确授权。

## 七文件只读预演

预演顺序为：

1. 重放最终 Prompt Package 的完整来源链；
2. 复验 pending、零授权 Handoff Proposal；
3. 核对 Receipt 的六份来源摘要、稳定 ID、recipient、ready 和 pending 状态；
4. 核对选择与 `handoff_authorized` 状态表；
5. 核对用户原文摘要；
6. 拒绝早于 Proposal 的 Receipt；
7. 拒绝低于 Proposal 或最终 Package 输入的数据分类，以及个人数据与 public 分类的组合；
8. 确认外部效果和高风险推导保持 false。

所有输入只读；没有模型、网络、进程、通知、文件创建或外部服务调用。

## 用户结果文案

预演不回显 `user_response`。三种互斥标题为：

- `confirmed`：**已收到 Handoff 确认，尚未交接**；展示接收者、精确 Package 范围、禁止动作、停止条件、Approval Points，以及外部效果仍未授权。
- `modify_requested`：**已收到 Handoff 修改请求，当前授权未成立**；说明原文件未修改，需形成新的完整 Package 和 Proposal 链。
- `rejected`：**已拒绝本次 Handoff，最终 Package 保持不变**；说明不会交给 Downstream Executor。

文案不得展示路径、摘要、Session/Package/Proposal/Confirmation ID、原始 Intent、Clarification 原答、用户确认原文、Evidence 来源、source refs、Review owner、decision maker ref 或内部字段路径。动态动作、停止条件和 Approval Point scope 必须经过共享 Markdown 安全层。

## 命令与退出码

```sh
ruby scripts/preview_handoff_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml
```

- `0`：七文件来源链、选择、时间和数据策略有效，安全结果文案写入 stdout；
- `1`：任一来源漂移、选择/授权组合非法、摘要/时间/数据策略无效，错误写入 stderr。

成功只证明用户针对精确 Handoff Proposal 的选择有效；不证明 Handoff 已发生、外部效果获批、用户身份、外部事实、下游交付或 PMind 商业效果。由于运行时和交接渠道尚未选定，下一边界是 confirmed-only、no-overwrite 的本地 Handoff Envelope 及其独立 lineage replay；Envelope 仍不得启动执行器或产生外部效果。

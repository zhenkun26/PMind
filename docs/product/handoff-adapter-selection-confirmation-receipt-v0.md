# Handoff Adapter Selection Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户对已通过十文件预演的精确 Adapter Selection Proposal 作出确认、修改或拒绝选择

## 目的

Adapter Selection Confirmation Receipt 把“用户看到的是哪一份 verified Envelope、reviewed Profile 与 pending Selection Proposal”和“用户随后选择了什么”保存为独立事实。confirmed 只记录一个 Adapter Profile 已被选中，不授权 dispatch、不批准任何 Profile 副作用，也不证明 Adapter 已实现或可用。

只读入口为 `scripts/preview_handoff_adapter_selection_confirmation.rb`，机器契约为 `schemas/handoff-adapter-selection-confirmation-receipt-v0.yaml`。

## 十一文件事实边界

```text
Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  + Persisted final Prompt Package
  + Handoff Proposal
  + Handoff Confirmation Receipt
  + Persisted Handoff Envelope
  + Reviewed Adapter Capability Profile
  + Pending Adapter Selection Proposal
  + Adapter Selection Confirmation Receipt
  → safe choice result
```

CLI 先完整重跑前十文件的 Selection Proposal 预演，并使用同一次重放产生的十份摘要校验第十一份 Receipt。Receipt 绑定：

- Session revision 至 Handoff Confirmation Receipt 的七份原始文件摘要；
- persisted Envelope、Adapter Profile 与 Selection Proposal 的精确文件摘要；
- Envelope、Profile 与 Proposal 的稳定 ID；
- Envelope `prepared`、Profile `reviewed`、Proposal `pending` 和 recipient；
- 用户选择原文及其 SHA-256；
- 捕获时间、数据分类、个人数据和密钥声明；
- 继续保持 unknown 的 personal-data / secret compatibility。

任一来源即使只改变等价 YAML 排版或注释，旧 Receipt 都会失效。修改 Envelope、Profile 或 Proposal 时必须生成新的确认边界。

## 选择状态表

| `confirmation_decision` | `adapter_selected` | 结果 |
| --- | --- | --- |
| `confirmed` | 必须为 `true` | 记录当前 reviewed Profile 已为当前 verified Envelope 选中 |
| `modify_requested` | 必须为 `false` | 当前未选择；修订或更换 Profile 并生成新 Proposal |
| `rejected` | 必须为 `false` | 当前候选终止；Envelope 保持不变 |

其他组合全部无效。所有状态都必须保持：

- `dispatch_authorized: false`；
- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- `effect_authorizations_granted: []`；
- `payload_data_attestation_required: true`；
- personal-data / secret compatibility 为 `unknown`；
- `contains_secrets: false`。

Receipt 保存逐字用户选择，因此 `contains_personal_data: true` 时不得使用 `public` 数据分类。

## confirmed 的精确语义

confirmed 表示用户在当前十文件事实基础上选择了一个 reviewed Profile。它不是 Adapter 凭据配置、健康检查、部署、启动、dispatch、回执或效果授权。

既有 Handoff authorization 只允许未来受控地交付 Envelope；它不能自动覆盖 Adapter Profile 中的本地写入、网络、进程、通知、外部服务、费用或生产数据副作用。每一个 true effect 都仍需独立明确授权。

由于现有 Envelope 不证明完整 payload 是否包含个人数据或密钥，即使用户确认 Profile，也必须保留 Payload Data Attestation 门禁。

## 用户结果文案

预演不回显 `user_response`。三种互斥标题为：

- confirmed：**已记录 Adapter 选择，尚未 dispatch**；展示 Profile 可读名称、selection 已记录、Envelope 仍为 prepared、dispatch 未授权、每项 true effect 未授权、兼容性 unknown 与 Payload Data Attestation 下一步。
- modify_requested：**已收到 Adapter 选择修改请求，当前未选择**；说明 Envelope 未改变，需修订/更换 Profile 并生成新 Proposal。
- rejected：**已拒绝当前 Adapter 候选**；说明 Envelope 保留、没有 Adapter 被选择、不会产生渠道副作用。

文案不得展示路径、摘要、Envelope/Profile/Proposal/Confirmation ID、reviewer ref、原始 Intent、Clarification 原答、用户确认原文、Evidence 来源、source refs、Review owner、decision maker ref 或内部字段路径。Profile display name 和 effect copy 必须使用受控词汇或共享 Markdown 安全层。

## 副作用、命令与退出码

预演器只读十一份本地 YAML，没有模型、网络、进程、通知、输出文件、费用、生产数据或外部服务调用。

```sh
ruby scripts/preview_handoff_adapter_selection_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml
```

- `0`：十一文件来源链、选择、时间和数据策略有效，安全结果文案写入 stdout；
- `1`：任一来源漂移、选择组合非法、权限扩大、摘要/时间/数据策略无效，错误写入 stderr。

成功不证明 Adapter 已实现、已配置、已 dispatch、已接收或产生结果，也不证明用户身份、外部事实或 PMind 商业效果。后续必须运行 [Handoff Payload Data Attestation v0](handoff-payload-data-attestation-v0.md)；兼容性通过后的下一边界是零授权 Adapter Effect Authorization Proposal，真实 Adapter 与 dispatch 继续后置。

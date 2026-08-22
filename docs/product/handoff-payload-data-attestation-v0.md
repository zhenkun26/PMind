# Handoff Payload Data Attestation v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户已确认一个 reviewed Adapter Profile 之后、任何副作用授权或 dispatch 之前

## 目的

Payload Data Attestation 记录对一个精确 Handoff Envelope payload 的完整数据审核结果，并按照已选择 Adapter Profile 的数据策略确定兼容或阻断。它把“数据可以由该渠道处理”与“渠道副作用已获授权”分开：即使兼容性通过，也不授权 dispatch、本地写入、网络、进程、通知、外部服务、费用、生产数据访问或高风险动作。

只读入口为 `scripts/preview_handoff_payload_data_attestation.rb`，机器契约为 `schemas/handoff-payload-data-attestation-v0.yaml`。

## 十二文件事实边界

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
  + Confirmed Adapter Selection Receipt
  + Payload Data Attestation
  → compatible-without-authorization or blocked result
```

CLI 先完整重跑前十一文件的 Adapter Selection Confirmation，再使用同一次重放的十一份字节摘要校验第十二份 Attestation。只有 `confirmed + adapter_selected: true` 可以进入本门禁。Attestation 额外绑定 Package、Envelope、Profile、Selection Proposal 与 Selection Confirmation 的稳定 ID、prepared/reviewed/pending 状态、recipient 和 Profile 的三项数据策略。

任一来源的字节、选择或策略发生变化，旧 Attestation 都会失效。等价 YAML 排版或注释变化也会改变摘要，因此必须重新审核。

## 完整审核与 provenance

`review_scope` 必须为 `complete_handoff_envelope_payload`，`review_status` 必须为 `completed`。未完成、抽样或只覆盖确认原文的审核不能生成有效 Attestation。

| `review_method` | `reviewer_ref` | `scanner_ref` / `scanner_version` |
| --- | --- | --- |
| `manual` | 必须提供 | 必须为 `not_applicable` |
| `automated` | 必须为 `not_applicable` | 必须提供 |
| `hybrid` | 必须提供 | 必须提供 |

这些引用只提供非敏感 provenance，不证明评审者身份、Scanner 质量或 Scanner 与真实 Adapter 实现的一致性。Attestation 不保存原始命中片段；只允许受控的个人数据与密钥类别代码，避免把敏感值复制到审核工件或用户文案。

## 兼容性矩阵

| Payload 事实 | Profile 策略 | 结果 |
| --- | --- | --- |
| Attestation 数据分类不高于 Profile 上限 | maximum classification | classification compatible |
| Attestation 数据分类高于 Profile 上限 | maximum classification | classification incompatible |
| 无个人数据 | `allowed` 或 `forbidden` | personal data compatible |
| 有个人数据 | `allowed` | personal data compatible |
| 有个人数据 | `forbidden` | personal data incompatible |
| 无密钥 | `forbidden` | secret compatible |
| 有密钥 | `forbidden` | secret incompatible |

`overall_data_compatibility` 只有在数据分类、个人数据和密钥三项都为 `compatible` 时才能为 `compatible`。存在个人数据或密钥时对应类别数组必须非空；不存在时必须为空。敏感 Payload 或含个人数据的 Attestation metadata 不得使用 `public` 分类，且 Attestation 分类不得低于 Envelope 或 Selection Confirmation。

v0 的“兼容”只覆盖 Profile v0 已声明的数据分类、个人数据和密钥策略。Profile v0 没有数据保留、地域/跨境导出或处理目的字段，因此 Attestation 不得声称这些维度已通过。引入远程或生产 Adapter 前必须先扩展 Profile 契约并重新生成选择与 Attestation 链。

## 权限不变量

所有兼容与不兼容结果都必须保持：

- `payload_data_attestation_completed: true`；
- `dispatch_authorized: false`；
- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- `effect_authorizations_granted: []`；
- `attestation_contains_secrets: false`。

Profile 的 `true` effect 只表示未来实现可能产生该副作用；Attestation 通过不能继承、推导或批准这些效果。

## 用户结果文案

兼容结果标题为 **Payload 数据审核已通过，仍未授权 dispatch**。只展示 Adapter 可读名称、完整审核范围、受控审核方式、个人数据/密钥是否兼容、true effect 仍未授权，以及下一步 Effect Authorization Proposal。

不兼容结果标题为 **Payload 数据与所选 Adapter 不兼容，dispatch 已阻断**。只展示受控阻断原因，不显示具体类别、命中内容、路径、摘要、内部 ID 或 provenance。选择记录仍存在，但必须移除/外置不兼容数据或选择新 Profile，并从受影响的 Proposal、Confirmation 与 Attestation 重新开始。

文案不得展示原始 Intent、Clarification 原答、Evidence 来源、Prompt Package 业务内容、个人数据/密钥类别、reviewer/scanner refs 或任何敏感片段。唯一动态可读名称必须经过共享 Markdown 安全层。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_payload_data_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml
```

- `0`：十二文件来源链、完整审核 provenance、Payload 事实和派生兼容性有效；兼容或阻断文案写入 stdout；
- `1`：未确认选择、来源漂移、审核不完整、兼容性伪报、权限扩大、时间或数据策略无效；错误写入 stderr。

预演器只读十二份本地 YAML，不扫描文件内容、不调用模型或 Scanner、不实现 Adapter，也不写文件、访问网络、启动进程、发送通知、产生费用或访问生产数据。输入 Attestation 必须来自经批准的独立审核流程；本仓库只验证其契约和 lineage，不证明 retention/export/purpose 合规。

下一最小边界 [Adapter Effect Authorization Proposal v0](handoff-adapter-effect-authorization-proposal-v0.md) 已实现：它逐项披露 Profile 中的 `true` effects 并请求选择，但 Proposal 自身继续保持零授权。真实 Adapter、凭据、健康检查、provider contract test 和 dispatch 仍后置。

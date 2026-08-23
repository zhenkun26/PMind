# Handoff Adapter Effect Authorization Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户已审阅一个 exact pending Effect Authorization Proposal 之后、Adapter 实现证明或 dispatch 之前

## 目的

Adapter Effect Authorization Confirmation Receipt 把用户对一份精确副作用 Proposal 的选择保存为不可变工件。它区分两件容易混淆的事：用户可以同意具名副作用，但这些副作用仍不可执行；只有后续实现证明、provider contract test、凭据/健康检查和独立 dispatch 确认全部通过后，执行路径才可能继续。

只读入口为 `scripts/preview_handoff_adapter_effect_authorization_confirmation.rb`，机器契约为 `schemas/handoff-adapter-effect-authorization-confirmation-receipt-v0.yaml`。

## 十四文件事实边界

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
  + Compatible Payload Data Attestation
  + Pending Adapter Effect Authorization Proposal
  + Adapter Effect Authorization Confirmation Receipt
  → named effect consent, still non-executable and non-dispatchable
```

CLI 先完整重跑十三文件 Effect Authorization Proposal，再用同一次重放的十三份字节摘要校验第十四份 Receipt。Receipt 绑定全部稳定 ID、prepared/reviewed/pending/confirmed/compatible 状态、recipient、Proposal 的 exact requested-effect 列表、费用披露和 retention/export/purpose 未核验边界。

任一来源字节、Profile effect、数据审核、Proposal 或选择发生变化，旧 Receipt 都会失效。等价 YAML 排版或注释变化同样改变摘要。

## 选择状态机

| `confirmation_decision` | `effect_authorization_confirmed` | `effect_authorizations_granted` | `all_requested_effects_authorized` |
| --- | --- | --- | --- |
| `confirmed` | `true` | 与 Proposal requested effects 完全相等 | `true` |
| `modify_requested` | `false` | `[]` | `false` |
| `rejected` | `false` | `[]` | `false` |

v0 不允许部分确认。缺少任一 requested effect、增加未请求 effect，或在修改/拒绝状态保留任何 grant 都是非法转换。零 effect Proposal 可以 confirmed；此时“全部已授权”表示用户确认了空集合，不表示产生了隐藏权限。

## 费用和生产数据派生

`cost_effect_authorized` 与 `production_data_access_authorized` 必须由“confirmed 且 requested effects 包含同名 effect”派生，不能单独设置。

即使费用 effect 被确认：

- `cost_limit_authorized` 固定为 false；
- 金额和上限没有被批准；
- Proposal 要求的 dispatch 前费用披露继续生效；
- 不进行金额计算或预算推断。

生产数据 effect 被确认只适用于 exact Payload 与 exact Profile，不扩大数据范围，也不修复 retention/export/purpose 缺口。

## 不可绕过的执行门禁

所有选择都必须保持：

- `adapter_implementation_attestation_required: true`；
- `provider_contract_test_required: true`；
- `dispatch_confirmation_required: true`；
- `effects_executable: false`；
- `dispatch_authorized: false`；
- `high_risk_authorization_inferred: false`；
- `retention_export_purpose_compatibility: not_attested`；
- `contains_secrets: false`。

具名 effect consent 是 dispatch 的必要条件之一，不是充分条件，也不能改变 Prompt Package 中已有 Approval Point。

## 用户原文和数据边界

Receipt 保存 `user_response` 及其 SHA-256，确保选择绑定到 exact 原文。预演结果不得回显原文。若原文含个人数据，`contains_personal_data` 必须为 true，且数据分类不得为 `public`；Receipt 不允许保存密钥。

Receipt 时间不得早于 Proposal，数据分类不得低于 Proposal。

## 用户文案

- confirmed：标题为 **已记录 Adapter 副作用授权，仍未授权 dispatch**；逐项显示“已记录授权；尚不可执行”，并展示费用、生产数据和剩余执行门禁。
- modify requested：标题为 **已收到 Adapter 副作用授权修改请求，当前零授权**；说明来源和 Profile 未被修改，必须重新生成受影响链。
- rejected：标题为 **已拒绝当前 Adapter 副作用请求**；说明没有 effect 获授权且路径在 dispatch 前停止。

文案不得展示用户原文、路径、摘要、内部 ID、原始 Intent、Payload 内容、审核 provenance 或自由文本 effect 描述。唯一动态 Adapter 名称必须经过共享 Markdown 安全层。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_effect_authorization_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml
```

- `0`：十三文件链、Receipt 绑定、选择矩阵、具名 grants、时间与数据策略有效；结果文案写入 stdout；
- `1`：来源漂移、部分/额外授权、非法选择、执行门禁绕过、原文摘要、时间或数据策略无效；错误写入 stderr。

预演器只读十四份本地 YAML，不创建或修改 Receipt，不执行 effect、不写文件、不访问网络、不启动进程、不发送通知、不产生费用、不访问生产数据，也不调用模型、Scanner 或 Adapter。

下一边界现已由 [Handoff Adapter Implementation Attestation v0](handoff-adapter-implementation-attestation-v0.md) 实现：它绑定 exact Profile、effect authorization Receipt 与提交的实现/contract-test 审核声明，派生兼容或阻断结果。该预演不装载实现、不运行测试；真实凭据、provider 健康检查和 dispatch 确认继续后置。

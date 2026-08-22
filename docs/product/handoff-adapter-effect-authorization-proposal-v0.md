# Handoff Adapter Effect Authorization Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact Payload Data Attestation 已兼容、任何副作用授权或 dispatch 之前

## 目的

Adapter Effect Authorization Proposal 把所选 Adapter Profile 的全部 `true` effects 转成一份可审阅、待确认、零授权的副作用披露。它解决“用户究竟被要求批准哪些效果”，不解决“用户已经批准了什么”。

只读入口为 `scripts/preview_handoff_adapter_effect_authorization.rb`，机器契约为 `schemas/handoff-adapter-effect-authorization-proposal-v0.yaml`。

## 十三文件事实边界

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
  → pending disclosure with zero authorization
```

CLI 先完整重跑十二文件 Payload Data Attestation，再用同一次重放的十二份字节摘要校验第十三份 Proposal。Attestation 必须是 `completed + compatible`；不兼容结果不能进入本阶段。Proposal 还绑定 Package、Envelope、Profile、Selection Proposal、Selection Confirmation 和 Attestation 的稳定 ID，以及 prepared/reviewed/pending/confirmed 状态。

任一来源字节、Profile effect、用户选择或数据审核结果变化，旧 Proposal 都会失效。等价 YAML 排版或注释变化同样改变摘要。

## Effect 集合不变量

`requested_effect_authorizations` 必须与所选 Profile 中值为 `true` 的 effect 集合完全相等，不能缺项、增项或以 Profile 的 `required_effect_authorizations` 之外的名称代替。Profile 自身仍由上游 Selection Preview 保证“每个 true effect 恰好有同名未来授权要求”。

v0 使用七个受控名称：

- `local_file_write`；
- `network_access`；
- `process_start`；
- `notification`；
- `external_service_write`；
- `cost_incurred`；
- `production_data_access`。

零 true effect 是合法状态，但只表示本阶段没有渠道副作用可批准；用户仍需确认这份披露，未来 dispatch 确认不能被跳过。

## 费用、生产数据与已知缺口

费用披露必须镜像 Profile：

- 无 `cost_incurred` 时，`cost_effect_present` 与 `cost_disclosure_required` 为 false，估算状态为 `not_applicable`；
- 有 `cost_incurred` 时，两项为 true，估算状态固定为 `not_estimated`，文案明确 dispatch 前仍需披露；
- v0 不填写或推断金额，因此没有浮点数、价格计算或虚构预算。

`production_data_access_disclosure_required` 必须与同名 true effect 一致。Proposal 不得把数据审核升级为生产访问授权。

Profile v0 仍没有 retention、地域/跨境 export 或 processing purpose 策略，因此 `retention_export_purpose_compatibility` 固定为 `not_attested`。该缺口不能被兼容 Attestation 或 Effect Proposal 隐式补齐。

## 状态机与权限不变量

本阶段只有一个合法状态：

```text
compatible Payload Data Attestation
  → pending Adapter Effect Authorization Proposal
  → future independent Confirmation Receipt
```

Proposal 必须固定：

- `proposal_status: pending`；
- `user_choice_status: not_recorded`；
- `effect_authorizations_granted: []`；
- `dispatch_authorized: false`；
- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- `proposal_contains_personal_data: false`；
- `proposal_contains_secrets: false`。

任何 `confirmed`、非空授权集合或 true 权限标志都是非法转换。Proposal 创建时间不得早于 Attestation，数据分类不得低于 Attestation。

## 用户文案

标题固定为 **Adapter 副作用授权提案待确认，当前零授权**。文案依序展示：

1. 每个 true effect 的受控名称和“待单独授权”；
2. 费用及生产数据访问的强制披露；
3. 零授权、未 dispatch、retention/export/purpose 未核验的当前边界；
4. 确认全部披露、请求修改、拒绝三种选项。

“确认”选项只允许后续建立独立 Confirmation Receipt，不在本预演中保存选择，也不 dispatch。文案不得展示路径、摘要、内部 ID、原始 Intent、原答、Payload 内容、审核 provenance 或自由文本 effect 描述。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_effect_authorization.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml
```

- `0`：十二文件链、兼容 Attestation、exact effect 集合、披露和零授权状态有效；pending 文案写入 stdout；
- `1`：来源漂移、不兼容 Attestation、effect 缺增项、披露不一致、越权状态、时间或数据策略无效；错误写入 stderr。

预演器只读十三份本地 YAML，不保存选择、不写文件、不访问网络、不启动进程、不发送通知、不调用模型/Scanner/Adapter、不产生费用，也不访问生产数据。

下一最小边界是独立 Adapter Effect Authorization Confirmation Receipt：它可以记录用户对精确 Proposal 的选择与具名 effect 授权，但仍不得自动 dispatch。真实 Adapter 实现还需要实现证明、provider contract test、凭据与健康检查边界；dispatch 必须有独立确认。

# Handoff Adapter Dispatch Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact ready Adapter Runtime Readiness Attestation 之后、任何 Dispatch Confirmation Receipt、Adapter 启动或 provider 调用之前

## 目的

Adapter Dispatch Proposal 是对一次精确 dispatch 的 pending、零执行决策工件。它把十六文件 ready runtime 链与 exact Handoff Envelope payload、Adapter/Profile/实现/环境、destination、幂等键、重试与超时、有效期、费用上限和强制停止条件绑定，供用户确认、修改或拒绝。

Proposal 不保存用户选择，不读取凭据，不访问运行环境，不执行健康检查，不启动 Adapter，不调用 provider，不写入外部系统，不产生费用，也不使任何 effect 可执行。

只读入口为 `scripts/preview_handoff_adapter_dispatch_proposal.rb`，机器契约为 `schemas/handoff-adapter-dispatch-proposal-v0.yaml`。

## 十七文件事实边界

```text
完整十六文件 Adapter Runtime Readiness Attestation 链
  + Adapter Dispatch Proposal
  → pending exact-dispatch decision
```

CLI 先重放完整十六文件链，只接受 `adapter_runtime_readiness_attestation_completed: true`、`runtime_evidence_reviewed: true` 和 `overall_runtime_readiness: ready`。随后以同次读取的十六份 SHA-256 校验第十七份 Proposal，并绑定稳定 ID、状态、recipient、Profile capabilities、实现身份、运行环境和 exact authorized effects。

任一来源文件的内容、注释或排版变化都会令旧 Proposal 失效。

## Exact payload、Adapter 与 destination

- payload 固定为 exact persisted Handoff Envelope 字节，其摘要必须等于十六文件链中的 Envelope digest；
- Adapter key、Profile capability、实现身份、Runtime Attestation 与 effect 集合必须与来源完全一致；
- `dispatch_destination_kind` 由 delivery mode 确定性派生；
- `dispatch_destination_ref` 是受控 destination provenance，不得为 `not_applicable`，也不得进入用户文案；
- v0 只接受声明支持幂等的 reviewed Adapter。

Proposal 验证引用格式和来源一致性，不访问 destination 或证明其存在。

## 幂等、尝试次数与超时

`idempotency_key_sha256` 由 exact payload/Profile/Implementation/Runtime digests、destination、时间窗口、尝试次数、超时和费用字段确定性派生。任何绑定变化都必须得到新 key，旧 Proposal 不能复用。

`dispatch_attempt_limit` 不得超过 Profile 的 retry capability；`retry.mode: none` 必须保持一次。`dispatch_timeout_seconds` 只是未来单次尝试的上限声明，不启动计时器或进程。

## 有效期与健康证据新鲜度

Proposal 有 `proposed_at`、`not_before`、`expires_at` 和由两端时间确定性派生的 `validity_seconds`：

- proposed 不得早于 Runtime Readiness review；
- not-before 不得早于 proposed；
- not-before 必须早于 expiry；
- 有效期为 60–86,400 秒。

当 Runtime Attestation 要求 provider health 时，Proposal 必须声明最大健康证据年龄，且该证据至少到 `not_before` 必须仍为 current。预演器只比较已提交时间，不重新执行健康检查。

最坏情况下的 `dispatch_attempt_limit × dispatch_timeout_seconds` 不得超过 `not_before` 到 `expires_at` 的可用窗口，避免 Proposal 在声明的尝试尚未完成前必然过期。

## 费用上限

当 exact effect 集合包含 `cost_incurred`：

- `cost_ceiling_required: true`；
- amount 必须是大于零、最多四位小数、无指数形式的十进制定点字符串；
- currency 必须是三位大写代码；
- `cost_limit_authorization_status: pending_confirmation`；
- `cost_limit_authorized: false`。

预演器不使用 float、不换汇、不计算税费或估算实际账单。无 cost effect 时，全部费用字段必须 `not_applicable`。

## 强制停止条件

Proposal 的 canonical stop-condition 集合至少包含：

- 来源字节、具名授权或 runtime readiness 变化；
- 尚未进入有效期或已过期；
- 幂等冲突；
- 请求未具名授权的 effect；
- delivery failure。

根据 exact dispatch 条件再加入 credential、provider health、cost ceiling 和 receipt failure。不得删除、增添或乱序，以免用户确认的边界与未来执行条件不一致。

## 不可绕过的权限门禁

所有合法 Proposal 固定：

- `dispatch_proposal_status: pending`；
- 用户选择未保存，Dispatch Confirmation Receipt 不存在；
- 预演器未访问环境、凭据或 provider；
- `effects_executable: false`；
- Adapter 未启动，provider 未调用；
- dispatch 未授权且未尝试；
- delivery receipt、外部写入和费用均未发生；
- 不推导高风险授权；
- Proposal 不含个人数据、密钥或 credential material。

## 用户文案规划

标题固定为 **Adapter dispatch 提案待确认，尚未调用 provider**。

文案展示受控 Adapter 名称、destination 类型、delivery/receipt、尝试次数、超时、有效期、费用上限、具名 effects、stop conditions 和三种选择；不泄漏路径、destination ref、摘要、幂等键、内部 ID、实现/runtime ref 或原始 payload。

- 确认：只允许未来创建独立 Dispatch Confirmation Receipt；
- 修改：调整精确 dispatch 条件并重建 Proposal；
- 拒绝：终止本次路径。

不得写“dispatch 已授权”“delivery 已开始”“provider 已调用”或“effect 正在执行”。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_dispatch_proposal.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml
```

- `0`：十七文件链、exact dispatch binding 与 pending state 自洽；stdout 输出待确认文案；
- `1`：runtime blocked、来源漂移、身份/能力错误、幂等/时间/健康/费用/stop-condition 矛盾、分类降级或权限绕过；stderr 输出受控错误。

预演器只读十七份本地 YAML。下一最小边界是独立 Adapter Dispatch Confirmation Receipt：记录用户对 exact Proposal 的 confirmed/modify/reject 选择，仍不得直接调用 provider。真实执行还需要 Service 强制重放来源、有效期、幂等、健康、凭据、费用与停止条件。

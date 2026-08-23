# Handoff Adapter Dispatch Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact pending Adapter Dispatch Proposal 之后、任何 Service execution request、Adapter 启动或 provider 调用之前

## 目的

Adapter Dispatch Confirmation Receipt 是用户对一次 exact Dispatch Proposal 的不可变选择记录。它把 confirmed、modify-requested 或 rejected 与全部十七份来源字节绑定；confirmed 只授权 Proposal 中固定的 payload、Adapter、destination、幂等键、时间窗口、尝试/超时、effects、费用上限和停止条件。

Receipt 不访问运行环境或凭据，不检查 provider，不启动 Adapter，不执行 effect，不尝试 dispatch，不创建 delivery receipt，不写外部系统，也不产生费用。机器契约为 `schemas/handoff-adapter-dispatch-confirmation-receipt-v0.yaml`，只读入口为 `scripts/preview_handoff_adapter_dispatch_confirmation.rb`。

## 十八文件事实边界

```text
完整十七文件 Adapter Dispatch Proposal 链
  + Adapter Dispatch Confirmation Receipt
  → exact dispatch authorization decision
```

CLI 每次先重放完整十七文件 Proposal，再以同次读取的全部 SHA-256 校验第十八份 Receipt。Receipt 同时镜像稳定 ID、ready/pending 来源状态、exact payload、delivery/receipt、destination、idempotency、时间、限制、effects、stop conditions 和 cost ceiling，供后续 Service 使用前再次逐项比较。

任一来源文件的内容、注释或排版变化都会令旧 Receipt 失效。修改任何 dispatch 条件必须生成新 Proposal 和新 Receipt，不能改写已确认工件。

## 选择状态机

| `confirmation_decision` | `dispatch_authorized` | cost-bearing Proposal 的 `cost_limit_authorized` | Service request / execution receipt required | 含义 |
|---|---:|---:|---:|---|
| `confirmed` | `true` | `true` | `true` | 只授权当前 exact dispatch 与 exact fixed-point ceiling |
| `modify_requested` | `false` | `false` | `false` | 返回 Proposal 阶段修改并重建完整下游链 |
| `rejected` | `false` | `false` | `false` | 本次路径在 execution request 前停止 |

无 cost effect 时，任何选择的 `cost_limit_authorized` 都必须为 `false`。Receipt 不推断其他金额、币种、税费、汇率、账单或重复 dispatch 的费用授权。

## 时间边界

- Receipt 不得早于 Proposal 的 `proposed_at`；
- confirmed 必须在 `expires_at` 之前被捕获，等于 expiry 也无效；
- 允许在未来排程的 `not_before` 之前确认；Service 仍不得提前执行；
- modify/reject 可以在 Proposal 过期后记录，因为它们不会建立授权；
- Receipt 不刷新 Proposal 时效。Service 必须按真实执行时刻重新检查 not-before、expiry 和健康证据。

## 确认与执行分离

confirmed Receipt 可以令 `dispatch_authorized: true`，并要求后续 Service request 与 execution receipt；modify/reject 必须把两个后续要求固定为 false。所有合法 Receipt 仍固定：

- `effects_executable: false`；
- Adapter 未启动、provider 未调用；
- dispatch 未尝试，delivery receipt 不存在；
- 外部写入与费用均未发生；
- 不推导高风险授权，不包含 secrets 或 credential material。

后续 Service execution request / preflight 必须重放 exact 十八文件链，并在任何 effect 可执行之前强制检查有效期、凭据、provider 健康、幂等冲突、费用预算和全部 stop conditions。执行结果必须进入独立 Receipt，不能回写本确认记录。

该边界由 [ADR 0003](../adr/0003-separate-dispatch-authorization-from-execution.md) 固定。

## 用户文案规划

confirmed 标题固定为 **已记录 Adapter dispatch 确认，尚未执行**。文案展示受控 Adapter 名称、destination 类型、delivery/receipt、尝试与超时、exact cost ceiling、具名 effects、stop conditions 和仍未发生的执行事实。

modify 标题为 **已收到 Adapter dispatch 修改请求，当前未授权**；reject 标题为 **已拒绝当前 Adapter dispatch**。

所有文案都不得回显文件路径、destination ref、摘要、idempotency key、内部 ID、user response、实现/runtime ref 或 payload 内容，也不得写“provider 已调用”“delivery 已完成”“费用已发生”。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_dispatch_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml
```

- `0`：十八文件链、exact binding、选择状态机、时间、费用和数据边界自洽；stdout 输出受控文案；
- `1`：上游 Proposal 无效、来源漂移、状态/身份/字段不一致、非法授权矩阵、过期确认、摘要或分类错误；stderr 输出受控错误。

预演器只读十八份本地 YAML。下一最小边界是 provider-neutral Service Adapter Dispatch Execution Request / Preflight：只接受未过期 confirmed Receipt，重新建立实时门禁并仍可产生 blocked 结果。真实 provider 调用与 delivery/cost 结果需要更后的受控执行器和 Execution Receipt。

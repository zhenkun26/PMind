# Handoff Adapter Dispatch Execution Preflight v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact confirmed Dispatch Receipt 之后、任何幂等预留、Adapter 启动或 provider 调用之前

## 目的

Adapter Dispatch Execution Preflight 是十九文件的临执行证据声明。它把 confirmed exact dispatch 与提交的有效期、凭据、provider 健康、destination、幂等可用性、effect scope 和费用预算检查绑定，并确定性派生 `ready` 或 `blocked`。

只读 preview 不执行这些外部检查，只验证已提交证据的格式、时间、来源、状态矩阵和派生结果。它不访问环境或凭据，不探测 provider/destination，不预留幂等键，不启动 Adapter，不尝试 dispatch，不写外部系统，也不产生费用。

机器契约为 `schemas/handoff-adapter-dispatch-execution-preflight-v0.yaml`，入口为 `scripts/preview_handoff_adapter_dispatch_execution_preflight.rb`。

## 十九文件边界

```text
完整十八文件 confirmed Dispatch Receipt 链
  + Adapter Dispatch Execution Preflight
  → ready | blocked submitted-evidence result
```

Preview 每次重放十八份来源，只接受 confirmed、`dispatch_authorized: true` 且要求 Service request 的 Receipt。第十九份文件绑定全部十八份字节摘要、核心身份、exact payload/destination/idempotency/time/effects/stops/cost ceiling，以及受控 reviewer/evidence provenance。

任一来源字节变化都会使旧 Preflight 失效；不得把新证据回填到旧文件。

## 派生门禁

- `checked_at` 不得早于 Dispatch Confirmation；
- checked 早于 not-before 时激活 `proposal_not_yet_valid`；达到或超过 expiry 时激活 `proposal_expired`；
- credential/provider health 是否 required 必须与 exact Runtime Attestation 一致；
- passed provider health 必须有不晚于 checked、且在 Proposal 最大年龄内的 submitted evidence；
- destination blocked 派生 `delivery_failure`；
- idempotency blocked 派生 `idempotency_conflict`，但 passed 也不代表已原子预留；
- effect scope blocked 派生 `unlisted_effect_requested`；
- cost effect 必须提交同币种 fixed-point estimate，并用四位定点整数与 confirmed ceiling 比较；超限派生 `cost_ceiling_would_be_exceeded`；
- active stop conditions 必须是 canonical 有序集合，不能增删或乱序。

active 集合为空才可得到 `overall_execution_preflight: ready` 与 `service_execution_gate_status: ready_for_service`。存在任一 blocker 就必须 blocked。

## Ready 仍不是执行

ready 才要求后续原子 attempt reservation 与 Execution Receipt。blocked 时两个后续要求都必须为 false，路径在执行前停止。

所有合法结果仍固定：preview 未访问 runtime/credential/provider/destination；幂等键未预留；effects 不可执行；Adapter 未启动；provider 未调用；dispatch 未尝试；delivery receipt、外部写入和费用均未发生。

Fixture 中的 passed/ready 只是合成声明，不是真实 Service 检查或可用性证明。

## 文案规划

ready 标题为 **Adapter dispatch Service preflight 声明已通过，仍未执行**，逐项标注“提交声明通过/不适用”，并明确幂等尚未预留。blocked 标题为 **Adapter dispatch Service preflight 声明未通过，执行已阻断**，只展示受控 blocker 文案。

文案不展示路径、destination ref、摘要、idempotency key、内部 ID、reviewer/evidence ref、健康证据 ref 或 payload 内容。

## 命令与退出码

```sh
ruby scripts/preview_handoff_adapter_dispatch_execution_preflight.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml
```

- `0`：十九文件链和 submitted evidence 自洽；ready 或 blocked 都是合法结果；
- `1`：非 confirmed Receipt、来源漂移、非法证据/派生矩阵、时间/费用/分类矛盾或越权状态。

本地参考边界现由 `handoff-adapter-local-reference-execution-v0.md` 实现：它只接受 local-file-only、zero-cost、无凭据/provider 的 exact ready 子集，在显式隔离根目录中原子发布 Envelope + Execution Receipt。它不证明 submitted Preflight 中的其他 provider 场景。

生产边界仍需要真实受控 Service：在执行瞬间重检 live stop conditions、使用 provider-specific Adapter，并无论成功/失败都创建不可变 Execution Receipt。真实凭据、provider、网络、生产写入或费用仍超出当前 standing authorization，不能由本地参考执行或 repository fixture 代替。

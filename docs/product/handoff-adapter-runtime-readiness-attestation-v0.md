# Handoff Adapter Runtime Readiness Attestation v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact compatible Adapter Implementation Attestation 之后、任何 Adapter Dispatch Proposal、真实环境访问或 provider 调用之前

## 目的

Adapter Runtime Readiness Attestation 是对一个精确 Adapter 实现及运行配置的已完成审核声明。它把十五文件实现链与提交的凭据引用、provider 健康、七项运行配置和 retention/export/purpose 证据绑定，得到 `ready` 或 `blocked`。

它不等于 PMind 亲自连通 provider。预演器不读取凭据，不访问运行环境，不启动进程，不执行健康检查，不调用 provider，不产生费用，也不使 effect 可执行或授权 dispatch。

只读入口为 `scripts/preview_handoff_adapter_runtime_readiness_attestation.rb`，机器契约为 `schemas/handoff-adapter-runtime-readiness-attestation-v0.yaml`。

## 十六文件事实边界

```text
完整十五文件 Adapter Implementation Attestation 链
  + Adapter Runtime Readiness Attestation
  → ready declaration or explicit runtime blocker
```

CLI 先重放完整十五文件链，只接受 `adapter_implementation_attestation_completed: true` 且 `overall_implementation_compatibility: compatible`。随后以同次读取的十五份 SHA-256 校验第十六份 Attestation，并绑定稳定 ID、状态、recipient、实现身份和 exact effect 集合。

任一来源文件的内容、注释或排版变化都会令旧 Runtime Readiness Attestation 失效。

## 运行配置审核

Attestation 声明一个 local process、container、managed service 或 remote API 环境引用，以及 manual、automated 或 hybrid 审核 provenance。七项配置分别覆盖：

- delivery；
- receipt；
- idempotency；
- retry；
- effect guard；
- data policy；
- cost policy。

只有七项全部 `compatible`，`runtime_configuration_compatibility` 才能为 `compatible`。不兼容是合法、不可变的阻断结果。

环境引用和 reviewer/scanner 引用是提交 provenance。预演器只验证格式和内部一致性，不读取引用目标，也不证明运行环境真实存在或已启动。

## 凭据引用边界

凭据审核只允许保存受控引用、可用状态、scope 兼容性和有效期状态；不得保存 key、token、secret、cookie、证书私钥或其他 credential material。

- `required` 只有在引用 available、scope compatible、expiry valid 时派生 `ready`；
- 其他组合派生 `blocked`；
- `not_required` 必须让全部凭据字段成为 `not_applicable`；
- notification、external-service write、cost 或 production-data access effect 不能把凭据要求降为 `not_required`。

`credential_readiness: ready` 表示提交声明自洽，不表示 PMind 读取、试用或认证了该凭据。

## Provider 健康证据边界

当 exact effect 集合包含 network、notification、external write、cost 或 production-data access 时，必须提交健康证据引用、摘要、检查时间与 healthy/unhealthy/unknown 状态。

`ready` 只在证据声明为 healthy、引用与摘要存在、检查时间合法时成立。检查时间不得早于 Implementation Attestation，也不得晚于 Runtime Readiness review。

预演器不执行检查、不访问 provider，也不独立证明 evidence digest 对应真实结果。

## Retention、export 与 purpose

上游 Profile v0 没有完整覆盖 retention/export/purpose。本阶段要求三个受控政策引用，并逐项声明 compatible/incompatible；三项全部兼容才将 `retention_export_purpose_compatibility` 从上游 `not_attested` 闭合为 `compatible`。

这些仍是提交审核结果，不是对外部系统配置的主动扫描。

## 结果与费用门禁

只有以下四层都不阻断，`overall_runtime_readiness` 才能为 `ready`：

- 七项运行配置兼容；
- 凭据引用证据 ready 或 not applicable；
- provider 健康证据 ready 或 not applicable；
- retention/export/purpose 全部兼容。

`cost_incurred` 不把 runtime ready 强制变成 blocked，但必须派生 `cost_limit_authorization_required: true` 与 `dispatch_cost_gate_status: pending_authorization`。本 Attestation 固定 `cost_limit_authorized: false`；费用上限只能在后续 dispatch 决策中单独确认。

## 不可绕过的权限门禁

所有合法结果固定：

- Runtime evidence 已由声明方审核，但预演器未访问运行环境；
- 预演器未读取凭据、未运行健康检查、未独立核验 provider；
- `effects_executable: false`；
- `dispatch_authorized: false`；
- `high_risk_authorization_inferred: false`；
- Adapter Dispatch Proposal 与独立 dispatch confirmation 仍为必需；
- Attestation 不含个人数据、密钥或 credential material。

`ready` 只允许建立下一份零 dispatch 的 Proposal；`blocked` 必须修复运行配置或证据并重建本 Attestation。

## 用户文案规划

- ready：标题为 **Adapter 运行时就绪声明已通过，仍未授权 dispatch**；明确 PMind 未访问环境/凭据、未执行健康检查，仅展示受控类型、分项结果与剩余门禁。
- blocked：标题为 **Adapter 运行时就绪声明未通过，dispatch 路径已阻断**；只展示受控阻断类别，不泄漏路径、摘要、内部 ID、环境引用、credential ref、health ref 或审核 provenance。

动态 Adapter 名称必须经过共享 Markdown 安全层。不得写“PMind 已连通 provider”“凭据已由 PMind 验证”“Adapter 正在运行”或“dispatch-ready”。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_runtime_readiness_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml
```

- `0`：十六文件链、审核 provenance 与派生结果自洽；stdout 输出 ready 或 blocked 文案；
- `1`：上游不兼容、来源漂移、身份/状态错误、派生矛盾、时间/分类降级或门禁绕过；stderr 输出受控错误。

预演器只读十六份本地 YAML。下一最小边界是 provider-neutral Adapter Dispatch Proposal：绑定精确 payload、Adapter、recipient、幂等键、费用上限、有效期与停止条件，保持 pending 与零 dispatch；真实执行仍需独立确认和受控 Service。

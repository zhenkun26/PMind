# Handoff Adapter Implementation Attestation v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact Effect Authorization Confirmation 已明确确认之后、任何凭据/健康检查、Runtime Readiness 或 dispatch 之前

## 目的

Adapter Implementation Attestation 是对一个精确 Adapter 实现身份的已完成审核声明。它把 reviewed Capability Profile、confirmed named effects、实现观察到的 effects，以及 provider contract-test 证据放进同一条可重放边界，得到 `compatible` 或 `incompatible` 结果。

它不等于运行时证明。预演器不装载或执行实现，不运行 contract-test suite，不读取凭据，不访问 provider，不做健康检查，也不授权 effect 或 dispatch。

只读入口为 `scripts/preview_handoff_adapter_implementation_attestation.rb`，机器契约为 `schemas/handoff-adapter-implementation-attestation-v0.yaml`。

## 十五文件事实边界

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
  + Confirmed Adapter Effect Authorization Receipt
  + Adapter Implementation Attestation
  → compatible declaration or explicit implementation blocker
```

CLI 重放完整十四文件授权链，并用同一次读取的十四份 SHA-256 校验第十五份 Attestation。Attestation 还必须绑定全部稳定 ID、prepared/reviewed/pending/confirmed/compatible 状态、recipient、Profile true effects、Receipt exact grants 和 retention/export/purpose 未核验边界。

任一来源文件的注释、排版或内容变化都会令旧 Attestation 失效。

## 实现身份与审核 provenance

Attestation 声明：

- `implementation_kind`：源码树、软件包、容器镜像或托管服务；
- `implementation_ref`、`implementation_version` 与 `declared_implementation_sha256`；
- 完整实现审核范围与 `completed` 状态；
- manual、automated 或 hybrid 审核方式；
- 与方式一致的 reviewer/scanner 引用。

这些字段是审核方提交的 provenance。预演器只验证格式和内部一致性，不读取 ref 指向的工件，也不独立证明 declared digest 与真实实现字节相等。

## 三层结果推导

### Profile effect conformance

`profile_declared_effects` 必须精确等于 Profile 的 true-effect 集合，`authorized_effects` 必须精确等于 confirmed Receipt grants。

`implementation_observed_effects` 可包含七个已知 effect 和受控的 `other`。预演器确定性派生：

- `missing_declared_effects = Profile true effects - observed effects`；
- `undeclared_effects_detected = observed effects - Profile true effects`；
- 两者都为空时 `profile_effect_conformance: conformant`，否则为 `nonconformant`。

零 effect 是合法集合，但仍不能跳过后续门禁。

### Provider contract evidence

Attestation 保存 suite/run/result 的受控引用和 result digest，并覆盖交付方式、回执、幂等、重试、副作用、数据、费用七个 Profile 维度。只有 `contract_test_status: passed` 且七项全部声明覆盖，`provider_contract_compatibility` 才能为 `compatible`。

失败或覆盖缺口是合法、可审计的阻断结果，不应通过伪造 PASS 来让文件失效或继续运行时路径。预演器验证声明，不执行测试。

### Overall compatibility

只有 effect conformance 与 provider contract compatibility 同时通过，`overall_implementation_compatibility` 才能为 `compatible`。其他组合必须为 `incompatible` 并阻断 Runtime Readiness。

## 不可绕过的运行时门禁

所有结果固定：

- 实现工件未被预演器装载；
- provider contract test 未被预演器执行；
- provider 凭据、健康和 Runtime Readiness 均未核验；
- `effects_executable: false`；
- `dispatch_authorized: false`；
- `high_risk_authorization_inferred: false`；
- Runtime Readiness Attestation 与独立 dispatch confirmation 仍为必需；
- retention/export/purpose 仍为 `not_attested`；
- Attestation 不含个人数据、密钥或 credential material。

`compatible` 只允许进入下一审查边界；`incompatible` 必须修复实现或重建受影响的 Profile、授权与证明链。

## 用户文案规划

- compatible：标题为 **Adapter 实现声明符合 Profile，仍未达到运行时就绪**；明确预演未装载实现/未运行测试，展示实现类型、审核方式、effect 符合结果及剩余门禁。
- incompatible：标题为 **Adapter 实现声明不符合要求，运行时路径已阻断**；只展示受控阻断类别，不泄漏实现 ref、路径、摘要、内部 ID 或自由文本证据。

动态 Adapter 名称必须经过共享 Markdown 安全层。

## 命令、退出码与副作用

```sh
ruby scripts/preview_handoff_adapter_implementation_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml
```

- `0`：十五文件链、审核 provenance 与派生结果自洽；stdout 输出 compatible 或 blocked 文案；
- `1`：来源漂移、身份/状态错误、非法 provenance、派生矛盾、时间/分类降级或门禁绕过；stderr 输出受控错误。

预演器只读十五份本地 YAML。下一最小边界是 provider-neutral Adapter Runtime Readiness Attestation：只接受 compatible Implementation Attestation，绑定凭据引用、provider 健康与运行时条件的独立证据；真实 dispatch 仍需单独确认。

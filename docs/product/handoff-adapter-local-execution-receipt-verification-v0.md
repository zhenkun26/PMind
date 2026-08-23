# Handoff Adapter Local Execution Receipt Verification v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: persisted local reference bundle and its exact nineteen-file source chain

## 目的

本契约提供独立、纯只读的 persisted Execution Receipt 审计。审计者提供原十九文件和 execution root；verifier 从 confirmed safe destination ref 推导 bundle，不接受任意 bundle 路径，不重新请求执行，也不要求当前时钟仍在已过期的 dispatch 窗口内。

入口为 `scripts/verify_handoff_adapter_local_execution_receipt.rb`。它与首次执行器共享 local-only scope、Receipt 构造、Schema 和时间顺序规则；执行器的幂等复用也调用同一个 verifier seam。

## 审计不变量

- 十九文件链仍可完整重放，Preflight 是 exact ready local-only 子集；
- execution root 已存在、非 symlink，并与仓库及来源隔离；
- 推导出的 bundle 是非 symlink `0700` 目录，恰好包含两个非 symlink `0600` 常规文件；
- Receipt 通过 Schema，全部十九份摘要、身份、destination、idempotency、effects、结果和 false provider/credential/network/process/cost 常量与 canonical Receipt 完全一致；
- delivered Envelope 与原第八份 exact 文件逐字节一致；
- `executed_at` 落在原 confirmed 窗口内，且不得早于 exact Preflight `checked_at`。

当前时间超过 `expires_at` 不会令一个当时合法的历史 Receipt 失效。改变来源、Preflight、payload、Receipt、权限、目录清单或 symlink 形态都会使审计失败；verifier 不修复、不覆盖、不删除损坏内容。

## 零写入与文案

verifier 只使用文件读取、`lstat/stat`、目录枚举、摘要和 YAML/Schema 校验，不创建锁、临时目录或任何文件。成功文案为 **本地参考 Execution Receipt 已独立验证**，说明已证明的本地事实和未证明的 provider/生产/校准/产品效果。

文案不显示路径、destination ref、摘要、幂等键、内部 ID 或 payload。

## 命令

```sh
ruby scripts/verify_handoff_adapter_local_execution_receipt.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT
```

- `0`：persisted bundle 与 exact historical chain 完全一致；
- `1`：来源、scope、root、inventory、权限、Schema、字段、payload 或时间顺序不一致。

成功只能证明该本地参考 bundle 自洽。后续可用 [Local Execution Verification Report v0](handoff-adapter-local-execution-verification-report-v0.md) 把一次真实审计结果写入独立、不可覆盖的本地报告；报告创建本身仍不是 provider 或效果证据。生产 provider receipt verification 需要 provider-specific immutable evidence、真实身份/租户、远端 receipt、shared idempotency 和费用记账契约，仍未实现或授权。

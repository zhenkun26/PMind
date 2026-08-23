# Handoff Adapter Local Execution Verification Report v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: one actual verification of an exact persisted local reference bundle

## 目的

本契约把一次成功的只读 persisted Receipt 审计固化为不可覆盖的 Execution Verification Report。报告不是“预期会通过”的声明：creator 必须先调用独立 verifier 重放十九文件与 bundle，再在最终写入前重复相同核验并比较 exact source、Envelope 和 Receipt 摘要。

机器契约为 `schemas/handoff-adapter-local-execution-verification-report-v0.yaml`，入口为 `scripts/create_handoff_adapter_local_execution_verification_report.rb`。调用方提供十九份来源、execution root 和一个独立 audit root；输出文件名由 exact Receipt 文件摘要和真实 `verified_at` 派生，不接受调用方指定文件名。

## 审计事件与时间

- `verified_at` 使用 creator 的当前时钟；CLI 不提供回填时间参数；
- `verified_at` 不得早于 persisted Receipt 的 `executed_at`；
- 历史 Receipt 可以在原 dispatch 窗口过期后审计，只要首次执行时间本来合法；
- 报告逐字节绑定十九份来源、delivered Envelope 和 Execution Receipt；
- 九项检查只有在实际 verifier 成功后才固定为 `passed`，outcome 固定为 `verified`。

创建前后若来源或 bundle 漂移，流程阻断且不创建报告。当前实现面向调用方独占、非对抗的本地文件系统；它不承诺跨进程锁或敌对文件系统下的线性化快照。

## 路径、持久化与恢复

audit root 必须已存在、可写、本身不是 symlink，并与仓库、十九份来源和 execution root 相互隔离。creator 在该根目录中用 `O_EXCL` 创建一个 `0600` YAML 文件并 fsync；已有同名结果永不覆盖。

报告如实记录这一次本地审计文件写入为 `local_audit_file_write_performed: true` 和 `external_write_performed: true`。它同时固定：来源和原 bundle 未被 creator 修改、dispatch 未重试、provider/credential/network/process/cost 未使用、高风险授权未推导。

写入失败只清理本次创建的半成品报告。creator 不删除或修复来源、bundle、audit root 中的既有文件。回滚已成功创建的报告需要操作者明确选择该精确文件；creator 自身不删除它。

## 文案规划

成功标题为 **本地 Execution Receipt 审计报告已创建**。正文只说明 exact historical bundle 已实际核验、报告已保存、本次未重新 dispatch，并明确未证明 provider 交付、生产就绪、校准结果或产品效果。

文案不显示 execution/audit 路径、destination ref、摘要、幂等键、内部 ID、Receipt 或 payload 内容。

## 命令

```sh
ruby scripts/create_handoff_adapter_local_execution_verification_report.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT AUDIT_ROOT
```

- `0`：两次 exact verifier 重放和最终快照一致，新的 `0600` 报告已持久化；
- `1`：来源、bundle、时间、路径、Schema、碰撞或写入不满足契约，未创建完整报告。

## 证据边界与后续

报告证明的是一个真实、带时间和字节绑定的本地审计事件，而不是 provider receipt authenticity、远端接收、生产身份/租户、共享幂等、费用记账、校准运行、用户采纳或 First-pass Delivery Success。

下一最小边界已由 [Local Execution Verification Report Verification v0](handoff-adapter-local-execution-verification-report-verification-v0.md) 实现：它重放来源与 bundle、校验报告 Schema/文件权限/确定性字段和审计时间，接受等价 YAML 排版但拒绝语义漂移。生产 provider verifier 仍需真实 provider-specific evidence 与新的明确授权。

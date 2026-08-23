# Handoff Adapter Local Execution Verification Report Verification v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: one persisted local Execution Verification Report and its exact evidence chain

## 目的

本契约让 persisted Verification Report 脱离 creator 自证。独立 verifier 先只读重放十九份来源和原 execution bundle，再校验调用方提交的精确报告文件，按报告自身的 `verified_at` 重建全部确定性字段并逐字段比较。

入口为 `scripts/verify_handoff_adapter_local_execution_verification_report.rb`。creator 与 verifier 只共享纯确定性的报告构造、Schema、摘要和时间规则；verifier 不实例化 creator，不进入 `File.open/chmod/delete` 写路径，也不读取当前时钟。

## 审计不变量

- 原十九文件与 persisted local bundle 必须先通过独立 Receipt verifier；
- 报告必须是常规、非 symlink、精确 `0600` 文件；
- 报告的直接父目录必须已存在、非 symlink，并与仓库、来源及 execution root 隔离；
- 报告通过 Schema，`verified_at >= receipt.executed_at`；
- 十九份来源摘要、Envelope/Receipt 摘要、身份、九项 passed check、outcome、真实本地写入与全部 false provider/credential/network/process/cost 常量必须等于确定性重建结果；
- 报告文件名必须等于 `<execution_verification_report_id>.yaml`。

当前时间可以晚于报告时间或原 dispatch expiry。等价 YAML 排版与注释可接受；任何语义、来源、bundle、权限、symlink、父目录或文件名漂移都会失败。

## 零写入与失败语义

verifier 只使用读取、`lstat/stat/realpath`、摘要、YAML/Schema 与逐字段比较。它不创建锁/目录/临时文件，不修复、覆盖、chmod、rename 或删除任何内容，也不重新执行 dispatch。

失败保留原状供调查。成功标题为 **本地 Execution Verification Report 已独立验证**，只说明报告准确记录对应本地审计事件，并继续明确未证明 provider 交付、生产就绪、校准结果或产品效果。

文案不显示路径、report/destination ref、摘要、幂等键、内部 ID、Receipt 或 payload。

## 命令

```sh
ruby scripts/verify_handoff_adapter_local_execution_verification_report.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT VERIFICATION_REPORT.yaml
```

- `0`：报告文件与 exact source/bundle replay 完全一致，全程零写入；
- `1`：来源、bundle、报告路径/权限、Schema、时间、字段或文件名不一致。

## 后续边界

本地 reference execution → Receipt → actual audit → persisted report → independent report verification 链已经闭合。后续不应默认继续增加本地审计包装层；下一轮应重新评估企业落地门禁，优先处理能产生真实新证据的校准参与者/Profile/workspace 输入，或在获得 provider/runtime/credential/write/cost 明确授权后设计真实 provider-specific verifier。

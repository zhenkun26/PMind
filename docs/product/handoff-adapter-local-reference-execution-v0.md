# Handoff Adapter Local Reference Execution v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: exact ready nineteen-file chain with local-file-only, zero-cost authority

## 目的

本契约把 PMind 从“提交的 Preflight 声明”推进到一个真实但严格隔离的本地参考执行：将 exact Handoff Envelope 字节和不可变 Execution Receipt 作为同一个 bundle 原子发布到调用方指定的本地根目录。

它用于验证 Service 执行语义，不是生产 provider Adapter。执行器不访问环境变量或凭据，不访问网络，不启动进程，不调用 provider，不使用生产数据，也不产生费用。

机器回执契约为 `schemas/handoff-adapter-local-execution-receipt-v0.yaml`，入口为 `scripts/execute_handoff_adapter_local_reference.rb`。原子 bundle 固定包含：

```text
EXECUTION_ROOT/
  <confirmed-safe-destination-ref>/
    delivered-envelope.yaml
    execution-receipt.yaml
```

## 强制能力边界

执行器只接受以下组合：

- 十九文件链可完整重放，Preflight 为当前 `ready_for_service`；
- 当前真实时钟满足 `not_before <= now < expires_at`，CLI 不提供回填时间参数；
- `delivery_mode: local_file`、`receipt_mode: local_digest`、`dispatch_destination_kind: local_path`；
- authorized effects 全部且仅为 `local_file_write`；
- credential 与 provider health 均为 `not_required`；
- cost ceiling 不适用，cost budget 为 `not_required`；
- destination ref 是以字母或数字开头的单个安全路径段；
- execution root 已存在、可写且本身不是符号链接，并与仓库及全部来源文件相互隔离。

任何 provider、网络、进程、凭据、费用、额外 effect、嵌套/遍历路径或过期 authority 都会在写入前阻断。

## 原子性与幂等

执行器先用 destination ref 的摘要创建根目录内锁目录，再在同一文件系统内创建 `0700` 临时目录。两个 `0600` 文件写入、flush/fsync 后，会再次检查十九份 exact 输入与当前时间，最后用目录 rename 一次性发布。

最终目录永不覆盖。相同目标再次调用时，执行器必须重新验证：目录非 symlink、恰好两个文件、权限、Receipt Schema、全部十九份摘要、身份/能力/结果常量、首次执行时间和 exact Envelope 字节。只有完全一致才返回“复用”，且本次不再次写入或执行。损坏、残缺或不同幂等内容一律阻断并原样保留供调查。

失败清理仅限同一 execution root 内本次创建且名称受控的临时目录与锁目录。执行器不删除最终 bundle，不修改十九份输入，也不清理调用方其他文件。

## Execution Receipt 语义

成功 Receipt 记录一次真实本地尝试：`adapter_started`、`dispatch_attempted`、`delivery_receipt_present`、`local_file_write_performed` 和 `external_write_performed` 为 true；执行 outcome 为 `succeeded`，幂等状态为 `committed`。

同一 Receipt 同时固定 `provider_called`、`credential_accessed`、`network_accessed`、`process_started`、`cost_incurred` 和高风险授权推导为 false，费用为零。它只能证明该隔离根目录内 exact Envelope 的本地发布，不能证明远端接收、provider 可用、企业集成、用户价值或 First-pass Delivery Success。

## 文案规划

首次成功标题为 **本地参考 dispatch 已原子完成**，明确唯一 effect 和仍未授权的生产边界。幂等重放标题为 **已验证并复用既有本地参考执行结果**，明确本次没有再次写入或执行。

两种文案都不显示根路径、destination ref、摘要、幂等键、内部 ID、Receipt 内容或源 Payload。

## 命令与恢复

```sh
ruby scripts/execute_handoff_adapter_local_reference.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT
```

- `0`：首次原子发布成功，或既有 exact bundle 已验证并复用；
- `1`：链无效、非当前时间窗、能力越界、路径不安全、预留冲突、写入失败或既有 bundle 不一致。

最终 bundle 是调用方隔离根目录内唯一新增的持久结果；如需回滚，只能由操作者明确选择并人工移除该精确目录。执行器自身不会删除或覆盖它。

## 后续边界

下一轮应实现独立、只读的 persisted Execution Receipt verifier，使审计者可在不重新请求执行的情况下验证 bundle。当前实现假设 execution root 由调用方独占且本地非对抗；共享敌对文件系统隔离不在本契约证明范围内。生产 provider executor 仍需明确 provider/runtime/credential/network/write/cost 范围、真实配置与独立验收，不能从本地参考成功推导。

# Prompt Package Creation v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 把一份已明确确认且通过 Quality Gate 的候选 Prompt Package 持久化为最终 Package

## 目的

Prompt Package Creator 闭合“用户确认”到“最终本地工件”的最小持久化边界。它只创建一个新的本地 YAML 文件，不改写四份来源，不执行 Handoff，也不调用模型、网络、进程、通知或外部服务。

命令入口为 `scripts/create_prompt_package.rb`。创建成功只证明当前五文件链满足本契约，不能证明 Package 中的外部事实正确、下游交付成功或 PMind 已通过商业验证。

## 五文件输入

Creator 接收：

1. 已完成来源链重放的 persisted `ready_to_compile` Session revision；
2. 通过 Prompt Package 与 Session→Package lineage 校验的候选 Package；
3. 绑定前两份精确文件的 Compilation Proposal；
4. 绑定前三份精确文件的 Compilation Confirmation Receipt；
5. 调用方指定、当前不存在的最终 Package 输出路径。

Creator 必须重跑完整四文件 [Compilation Confirmation Receipt](prompt-package-compilation-confirmation-receipt-v0.md) 预演，不能只读取 Receipt 的授权布尔值。

## 唯一允许状态

创建仅在以下三项同时成立时允许：

- `confirmation_decision: confirmed`；
- `draft_package_handoff_ready: true`；
- `package_creation_authorized: true`。

`confirmed + not-ready`、`modify_requested`、`rejected`、来源摘要漂移、Schema/lineage 无效或非法授权组合都必须在打开输出文件前失败，并保持零写入。

## 最终 Package 内容

最终 Package 必须是候选 Package 的语义深拷贝，只允许新增可选顶层 `compilation`：

- 创建时间使用 Confirmation Receipt 的 `captured_at`；
- 保存 Session ID、revision number 和 Session 文件摘要；
- 保存候选 Package 文件摘要；
- 保存 Compilation Proposal ID 与文件摘要；
- 保存 Compilation Confirmation ID 与 Receipt 文件摘要；
- 固定 `confirmation_decision: confirmed`；
- 固定 `handoff_authorization_inferred: false`；
- 固定 `high_risk_authorization_inferred: false`。

Creator 不得修改 `package_id`、`created_at`、Intent、Scope、Evidence、Recommendation、Acceptance Criteria、Approval Point、`handoff.ready` 或任何允许/禁止动作。写入前必须再次运行最终 Package 校验和 Session→Package lineage 校验。

## 文件安全

- 输出使用原子排他的 create-if-absent 语义；已有路径一律拒绝覆盖。
- 新文件权限固定为 `0600`。
- 写入后执行 flush 与 fsync。
- 写入异常只清理由本次调用已经新建的不完整输出；不得删除已有路径或任何输入。
- 不自动创建缺失的父目录，避免扩大持久化范围。

## 用户结果文案

成功文案使用标题 **最终 Prompt Package 已创建**，并明确：

- 候选源文件保持不变；
- Package Quality Gate 为可交接；
- 当前只完成本地创建，尚未 Handoff；
- Approval Point scope 与状态保持不变；
- Handoff 决策前仍须按 [Prompt Package Lineage Verification v0](prompt-package-lineage-v0.md) 独立重放 persisted Package lineage。

动态 Approval Point scope 必须通过共享 Markdown 安全层。文案不得展示路径、摘要、Session/Package/Proposal/Confirmation ID、原始 Intent、问题原答、用户确认原文、Evidence 来源、source refs、Review owner 或 decision maker ref。

## 命令与退出码

```sh
ruby scripts/create_prompt_package.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml OUTPUT.yaml
```

- `0`：完整来源链有效，状态允许创建，最终 Package 已以 `0600` 写入新路径，安全文案写入 stdout；
- `1`：输入、状态、lineage、输出路径或写入无效，仅在 stderr 返回不回显用户内容的错误。

最终 Package 在独立 lineage replay 通过前不得进入 Handoff 决策。Creator 本身不执行该审计，也不授权提交、推送、部署、发送消息、外部服务写入、费用、生产数据访问或权限提升。

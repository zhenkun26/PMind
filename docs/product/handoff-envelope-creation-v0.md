# Handoff Envelope Creation v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已明确确认且完整来源链仍有效的 Handoff，在真实交付前生成本地可移植封装

## 目的

Handoff Envelope 把一份精确最终 Prompt Package 和授权它的七文件 lineage 封装为单个本地文件。它是后续 provider-specific adapter 的输入边界，不是一次 Handoff 事件、执行记录或下游接收证明。

confirmed-only Creator 为 `scripts/create_handoff_envelope.rb`，机器契约为 `schemas/handoff-envelope-v0.yaml`。

## 八文件创建边界

```text
Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  + Persisted final Prompt Package
  + Handoff Proposal
  + Handoff Confirmation Receipt
  → new local Handoff Envelope
```

Creator 先重跑完整 Handoff Confirmation Preview。只有 `confirmation_decision: confirmed` 与 `handoff_authorized: true` 同时成立才允许继续；`modify_requested`、`rejected`、任一来源漂移或无效数据策略都必须零写入。

输出路径必须尚不存在。Creator 以排他创建方式写入 `0600` 文件，永不覆盖输入或已有输出；写入失败时清理本次可能产生的不完整文件。所有七份来源只读。

## Envelope 内容

Envelope 固定包含：

- 从 Handoff Confirmation ID 确定性映射的 Envelope ID；
- Confirmation Receipt 的 `captured_at`，不读取当前时钟；
- `delivery_state: prepared`；
- 精确最终 Prompt Package 的完整副本；
- Handoff Proposal 与 Handoff Confirmation 的稳定 ID；
- Session、候选 Package、Compilation Proposal、Compilation Confirmation Receipt、最终 Package、Handoff Proposal 与 Handoff Confirmation Receipt 的七份文件 SHA-256；
- `handoff_authorized: true`，以及保持为 false 的外部效果与高风险推导字段；
- Receipt 已验证的数据分类，以及明确标为仅适用于确认原文的个人数据和 secrets 声明。

Envelope 不保存来源路径或用户确认原文。`confirmation_contains_personal_data` 与 `confirmation_contains_secrets` 只复述 Confirmation Receipt 对确认原文的声明，不得解释为对内嵌 Package 的全局内容扫描结果。内嵌 Package 可能包含原始 Intent、Clarification、Evidence 和其他业务内容，因此 Envelope 的访问控制不得低于其声明分类；本地 `0600` 只是当前实验阶段的最低文件权限，不替代生产环境的租户隔离、加密、密钥管理和审计。

Schema 对 Envelope 外壳和授权 metadata 做结构校验；Creator 另用完整 Prompt Package Validator 校验内嵌 Package，并核对 Package ID 与 recipient。这样避免复制整份 Prompt Package Schema，同时保持单一机器契约来源。

## 确定性与权限边界

相同的七份输入在不同新路径产生逐字节相同的 Envelope。以下状态始终成立：

- Envelope 已准备，但尚未交付；
- Downstream Executor 未启动；
- 没有模型、网络、子进程、通知或外部服务调用；
- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- Prompt Package 中的 Approval Points、禁止动作与停止条件保持不变。

Handoff 授权允许未来受控适配器交付这份精确 Package，但不自动授权适配器渠道产生的网络、消息、提交、推送、部署、费用、生产数据访问或其他外部效果。实际渠道未选择前不得把 Envelope 描述为“已发送”“已接收”或“执行中”。

## 用户结果文案

成功标题固定为 **Handoff Envelope 已创建，尚未交接**。文案只展示：

1. 已准备、未交付状态；
2. 人类可读接收者；
3. 封装的是精确 Package 与七文件授权 lineage；
4. 禁止动作、停止条件和 Approval Points；
5. 尚未启动执行器、产生外部效果或批准高风险动作；
6. 下一步必须独立重放 lineage。

文案不得展示路径、摘要、Envelope/Session/Package/Proposal/Confirmation ID、用户确认原文、原始 Intent、Clarification 原答、Evidence 来源、source refs、Review owner、decision maker ref 或内部字段路径。动态内容必须经过共享 Markdown 安全层。

## 命令与退出码

```sh
ruby scripts/create_handoff_envelope.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml OUTPUT.yaml
```

- `0`：完整七文件确认链有效且明确授权，在新路径创建有效 `0600` Envelope，安全文案写入 stdout；
- `1`：来源/摘要/状态/数据策略无效、未确认、输出已存在或写入失败，错误写入 stderr 且不得保留新产物。

成功只证明本地 Envelope 已按确认链准备完成；不证明真实 Handoff、下游接收、执行、外部效果、事实正确、Approval Point 获批或 PMind 商业效果成立。下一实现边界是独立 Handoff Envelope lineage verifier；验证器仍不得启动执行器或访问外部渠道。

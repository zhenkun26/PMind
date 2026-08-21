# Prompt Package Lineage Verification v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已持久化最终 Prompt Package 的独立来源链重放审计

## 目的

创建时校验只能证明当时的输入和输出一致。Prompt Package Lineage Verification 允许后续操作者或 Handoff 决策步骤重新提供五份文件，证明 persisted Package 仍能由同一组已确认来源确定性重建，并且 `compilation` metadata、业务内容和授权边界都未发生篡改。

参考实现为 `scripts/verify_prompt_package_lineage.rb`。它只读五份 YAML，不创建报告、不修改任何输入、不执行 Handoff，也不调用模型、网络、进程、通知或外部服务。

## 五份输入

```text
Persisted Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  → deterministic reconstruction
  ↔ Persisted final Prompt Package
```

验证器执行：

1. 复用 Creator 的无写入 seam，重跑 Session、候选 Package、Proposal 与 Confirmation 的完整绑定、状态、时间、数据和 lineage 校验；
2. 要求选择为 `confirmed`、候选 `handoff.ready: true` 且允许本地 Package 创建；
3. 确定性重建期望最终 Package；
4. 独立校验 persisted Package 的 Schema、业务不变量和 Session→Package lineage；
5. 逐字段核对 `compilation` metadata；
6. 比较除 `compilation` 外的完整 Package 内容。

四份来源继续按文件字节 SHA-256 绑定。Persisted Package 本身按解析后的 YAML 结构比较，因此等价的缩进、注释、引号或字段排版变化不会失败；任何数组顺序、Intent、Scope、Evidence、Recommendation、Acceptance Criteria、Approval Point、Handoff 或 lineage 值变化都会失败。

## 审计结果状态

| 输入状态 | 结果 | 后续动作 |
| --- | --- | --- |
| 五文件有效且内容可确定性重建 | `verified` | 可进入受控 Handoff 决策 |
| 任一来源摘要、ID、revision 或确认漂移 | `invalid` | 停止，恢复原始工件或重新提案与确认 |
| Persisted Package 结构或 Session lineage 无效 | `invalid` | 停止，不得用于 Handoff |
| `compilation` metadata 与来源不一致 | `invalid` | 视为 lineage 篡改或错误归档 |
| Package 业务内容与重建结果不一致 | `invalid` | 视为未确认变更，不得继续 |

验证器不修复失败，也不选择“最可信版本”。需要修改 Package 时必须形成新的候选 Package、Compilation Proposal、Confirmation Receipt 和最终 Package，不能覆盖审计失败的工件。

## 用户可见审计文案

成功时 stdout 使用标题 **Prompt Package 来源链已验证**，并依次说明：

1. 四份来源绑定、用户确认和确定性重建均匹配；
2. Package Quality Gate 为可交接；
3. Approval Point scope 与状态保持不变；
4. 下一步只能创建并预演精确绑定最终 Package 的 [Handoff Proposal v0](handoff-proposal-v0.md)，验证本身不执行或授权 Handoff。

动态 Approval Point scope 必须经过共享 Markdown 安全层。文案不得展示路径、摘要、Session/Package/Proposal/Confirmation ID、原始 Intent、问题原答、确认原文、Evidence 来源、source refs、Review owner、decision maker ref 或字段路径。

失败只写入 stderr，供操作者诊断；错误同样不得回显原始 Intent、用户答案、确认原文或 Evidence 内容。

## 命令与退出码

```sh
ruby scripts/verify_prompt_package_lineage.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml
```

- `0`：五文件有效，persisted Package 与确定性重建逐字段一致，安全审计文案写入 stdout；
- `1`：任一输入不可读、链路无效、metadata 不匹配或 Package 内容漂移，仅在 stderr 返回错误。

验证通过只证明最终 Package 的可重放来源链完整；不证明用户身份、外部事实正确、Handoff 已授权或发生、待审批动作获批、下游交付成功或 PMind 商业效果成立。后续 Handoff Proposal 必须重新执行这份五文件验证，并绑定同一次读取的最终 Package 字节摘要。

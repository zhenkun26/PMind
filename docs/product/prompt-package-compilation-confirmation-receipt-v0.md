# Prompt Package Compilation Confirmation Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 用户对已通过预演的 Prompt Package Compilation Proposal 作出确认、修改或拒绝选择

## 目的

Compilation Confirmation Receipt 把“用户看到了哪一份精确编译提案”和“用户随后选择了什么”保存为独立事实。它不复制候选 Package 内容，不把确认解释为 Handoff，也不改变任何 Approval Point。

只读预演入口为 `scripts/preview_prompt_package_compilation_confirmation.rb`。本阶段只验证 Receipt 和生成结果文案；即使选择有效且允许创建，也不会写入最终 Package。

## 四层事实边界

1. **Session revision**：已确认并完成来源链重放的澄清结果。
2. **Candidate Prompt Package**：依据 Session 编译并通过自身契约与跨工件 lineage 的候选内容。
3. **Compilation Proposal**：绑定两个精确文件并展示范围、方案、验收、未知项、审批边界和候选质量门。
4. **Compilation Confirmation Receipt**：用户针对该份 Proposal 的逐字选择。

确认不能反向改写 Session、Package 或 Proposal。修改请求必须形成新的候选 Package 和 Proposal；拒绝必须保留 Session revision，且不得创建最终 Package。

## 精确文件绑定

机器结构位于 `schemas/prompt-package-compilation-confirmation-receipt-v0.yaml`。Receipt 同时绑定：

- Session ID、`ready_to_compile` 状态、revision number 与 Session 文件摘要；
- Package ID、候选 `handoff.ready` 与 Package 文件摘要；
- Compilation Proposal ID 与 Proposal 文件摘要；
- 用户确认原文与原文 SHA-256；
- 捕获时间、语言、数据分类、个人数据和 secrets 声明；
- `handoff_authorized: false` 与 `high_risk_authorization_inferred: false`。

三个来源摘要均按文件字节计算。任一来源即使只改变注释、空格、换行或字段顺序，旧 Confirmation Receipt 也会失效；必须重新预演并获得新选择。

## 选择与创建权限状态表

| `confirmation_decision` | 候选 `handoff.ready` | `package_creation_authorized` | 结果 |
| --- | --- | --- | --- |
| `confirmed` | `true` | 必须为 `true` | 后续 confirmed-only creator 可以继续 |
| `confirmed` | `false` | 必须为 `false` | 只记录理解一致；修正 Quality Gate 后重新提案 |
| `modify_requested` | 任意 | 必须为 `false` | 当前提案暂停，形成新候选和 Proposal |
| `rejected` | 任意 | 必须为 `false` | 当前编译终止，保留 Session revision |

其他组合全部无效。`package_creation_authorized: true` 只授权未来在用户指定的新本地路径创建与当前候选内容一致的最终 Package；它不授权 Handoff、提交、推送、部署、发送消息、外部服务修改、费用、生产数据访问或权限提升。

## 四文件预演

CLI 会先重跑完整 [Prompt Package Compilation Proposal v0](prompt-package-compilation-proposal-v0.md) 预演，再验证 Confirmation Receipt：

1. 四份 YAML 均可安全解析；
2. Session、Package、Session→Package lineage 和 Compilation Proposal 仍然有效；
3. Receipt 的全部 ID、revision number、候选质量门状态和三个来源摘要匹配；
4. `package_creation_authorized` 与选择/质量门状态表一致；
5. 用户原文摘要匹配；
6. Receipt 不早于 Proposal；
7. 数据分类与个人数据声明不低于来源；
8. Handoff 和高风险授权声明保持为 false。

所有输入只读；没有模型、网络、进程、通知或外部服务调用。

## 用户结果文案

预演不回显 `user_response`。不同结果使用互不混淆的标题：

- confirmed + ready：**已收到 Package 创建确认，尚未创建最终 Package**；说明只允许后续本地受控创建，Handoff 和待审批动作仍保持分离。
- confirmed + not-ready：**已确认当前编译理解，但候选 Package 尚未就绪**；说明不会授权创建可交接 Package，修正后必须重新提案和确认。
- modify requested：**已收到 Package 修改请求，当前编译提案不会继续**；说明原工件未修改。
- rejected：**已拒绝本次 Package 编译，Session revision 保持不变**；说明不会生成最终 Package 或 Handoff。

文案不得展示文件路径、摘要、Session/Package/Proposal/Confirmation ID、原始 Intent、问题原答、用户确认原文、Evidence 来源、source refs、字段路径、Review owner 或 decision maker ref。confirmed + ready 文案可以展示用户已经见过的 Approval Point scope 与状态，但必须通过共享 Markdown 安全层。

## 命令与退出码

```sh
ruby scripts/preview_prompt_package_compilation_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml
```

- `0`：四文件链路、选择、时间和数据策略有效，安全结果文案写入 stdout；
- `1`：任一来源漂移、选择组合非法、摘要/时间/数据策略无效，仅在 stderr 返回不回显用户原文的错误。

成功不表示最终 Package 已创建、Package 内容或外部事实正确、Handoff 已发生、高风险动作已批准、下游交付成功或 PMind 商业效果成立。下一阶段若实现 creator，必须为 confirmed-only、no-overwrite、本地 `0600` 创建，并另行设计 persisted Package lineage replay。

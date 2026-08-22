# Handoff Envelope Lineage Verification v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 本地 Handoff Envelope 创建后、任何渠道适配或真实交付前的独立只读审计

## 目的

Handoff Envelope lineage verifier 不因文件存在就信任它。验证器重新读取七份来源，复用 Creator 的无写入构建 seam 确定性重建期望 Envelope，再独立校验并逐字段核对 persisted Envelope。

只读入口为 `scripts/verify_handoff_envelope_lineage.rb`。结构契约继续使用 `schemas/handoff-envelope-v0.yaml`，内嵌 Package 继续使用完整 Prompt Package Validator，避免产生第二份 Package Schema 真相源。

## 八文件验证边界

```text
Session revision
  + Candidate Prompt Package
  + Compilation Proposal
  + Compilation Confirmation Receipt
  + Persisted final Prompt Package
  + Handoff Proposal
  + Handoff Confirmation Receipt
  + Persisted Handoff Envelope
  → safe lineage verification result
```

验证顺序为：

1. 读取 persisted Envelope 的原始字节并安全解析 YAML；
2. 通过 Creator 的 `build_files` seam 重跑完整七文件 confirmed-only 链，不写输出；
3. 独立运行 Envelope Schema；
4. 独立运行内嵌 Prompt Package Validator，并核对 Package ID 与 recipient；
5. 逐字段比较 Envelope metadata；
6. 逐字段比较 authorization metadata，包括七份文件摘要和两个稳定 ID；
7. 比较完整内嵌 Prompt Package 业务内容。

任一阶段失败都不得继续到 Adapter。验证器不会修改、修复、重排或重新保存任何输入。

## 等价与漂移

比较基于安全解析后的业务结构，因此只改变注释、空白、字段顺序或其他等价 YAML 排版可以通过。以下变化必须拒绝：

- 七份来源中的任一字节变化使原绑定失效；
- Envelope ID、时间、Package ID、recipient、数据分类或 `prepared` 状态漂移；
- Handoff Proposal/Confirmation ID 或任一来源摘要漂移；
- Handoff、外部效果或高风险推导字段越权；
- 确认原文数据声明被改写；
- 内嵌 Package 的 Intent、Evidence、Recommendation、Acceptance Criteria、Approval Points、禁止动作、停止条件或其他业务内容变化；
- Schema 字段缺失、新增、类型错误或畸形 YAML。

验证成功不证明 Package 中的事实真实，只证明 persisted Envelope 与其已确认来源可以确定性对应。

## 用户结果文案

成功标题固定为 **Handoff Envelope 来源链已验证，仍未交接**。文案只展示：

1. 七份来源绑定匹配；
2. 用户 Handoff 选择为已确认；
3. Envelope metadata 与内嵌 Package 均和确定性重建一致；
4. 当前状态仍是已准备、未交付；
5. 禁止动作、停止条件和 Approval Points；
6. 下一步只能探索 provider-specific Adapter 契约。

文案不得展示路径、摘要、Envelope/Session/Package/Proposal/Confirmation ID、原始 Intent、Clarification 原答、用户确认原文、Evidence 来源、source refs、Review owner、decision maker ref 或内部字段路径。动态内容必须经过共享 Markdown 安全层。

## 副作用边界

验证器没有文件写入、模型、网络、子进程、通知或外部服务调用。它不选择 Adapter、不启动 Downstream Executor、不生成交付回执，也不将已有 Handoff 授权扩大为渠道副作用授权。

真实 Adapter 若需要网络、消息、进程、提交、推送、部署、费用、生产数据访问或其他外部效果，必须拥有独立契约、失败/重试/幂等策略、接收证明和相应授权。

## 命令与退出码

```sh
ruby scripts/verify_handoff_envelope_lineage.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml
```

- `0`：七份来源可重放，persisted Envelope 的 Schema、metadata、authorization 与完整 Package 内容全部匹配，安全文案写入 stdout；
- `1`：任一输入不可读/无效、来源漂移、重建失败或 persisted Envelope 不一致，错误写入 stderr。

成功只允许进入 Adapter 产品与契约探索；它不证明真实 Handoff、接收、执行、外部效果、事实正确、Approval Point 获批或 PMind 商业效果成立。

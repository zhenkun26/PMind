# Handoff Adapter Selection Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 精确 Handoff Envelope 来源链已验证，且候选 Adapter Capability Profile 已审查

## 目的

Adapter Selection Proposal 把一份精确 verified Envelope 与一份精确 reviewed Profile 绑定到 pending、零副作用的用户决策边界。只读入口为 `scripts/preview_handoff_adapter_selection.rb`，结构契约为 `schemas/handoff-adapter-selection-proposal-v0.yaml`。

Proposal 不是 Adapter Selection Confirmation、dispatch 命令、执行记录或交付回执。

## 十文件预演边界

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
  → safe selection copy
```

预演器必须：

1. 重跑前八份文件的完整 Envelope lineage verification；
2. 使用 verifier 同一次读取的 Envelope 原始字节计算 Proposal 绑定；
3. 安全读取 Profile 与 Proposal，并分别运行 Schema；
4. 复核 Profile 的副作用授权、回执、幂等、重试、成本和 reviewed 状态；
5. 核对 Envelope/Profile 的稳定 ID、原始文件摘要、`prepared` 状态、接收者和 reviewed 状态；
6. 拒绝早于 Envelope、Profile 创建或 Profile 审查的 Proposal；
7. 拒绝 Profile 或 Proposal 对 Envelope 数据分类的降级；
8. 只在全部校验通过后生成用户文案。

任一步失败都不得自动修复来源、保存选择或继续 dispatch。

## Proposal 状态

有效 Proposal 必须固定为：

- `confirmation.required: true`；
- `confirmation.status: pending`；
- `adapter_selected: false`；
- `dispatch_authorized: false`；
- `external_effects_authorized: false`；
- `high_risk_authorization_inferred: false`；
- 个人数据兼容性与密钥兼容性均为 `unknown`。

确认选项只允许未来独立步骤记录用户对这份精确 Profile 的选择。它不会继承或扩大既有 Handoff 授权，也不会批准 Profile 中列出的任何副作用。

## 用户文案规划

成功标题固定为 **Handoff Adapter 选择提案待确认，尚未选择或交付**。文案只展示：

- Profile 可读名称；
- 交付方式、接收证明、幂等支持和重试上限；
- 未来 dispatch 会产生且仍未授权的副作用；
- Envelope 分类与 Profile 最高分类；
- 个人数据和密钥兼容性未知；
- 确认候选、请求修改、拒绝候选三种选择；
- 当前未选择、未 dispatch、未授权外部效果或高风险动作。

动态名称必须通过共享 Markdown 安全层。不得展示路径、摘要、内部 ID、原始 Intent、Clarification 原答、确认原文、Evidence 来源、source refs、Review owner、decision maker ref 或 Prompt Package 内部字段路径。

## 副作用与下一边界

预演器是十文件只读过程，没有模型、网络、子进程、通知、外部服务调用或输出文件创建。合成 Fixture 不是实际 Adapter、真实用户选择、交付记录或产品效果证据。

独立 [Adapter Selection Confirmation Receipt v0](handoff-adapter-selection-confirmation-receipt-v0.md) 现已实现：confirmed 也只能证明“选中了哪份 Profile”，仍不能 dispatch。由于 Envelope 尚无覆盖完整 Package 的个人数据/密钥声明，下一边界是 provider-neutral Payload Data Attestation；此后仍需对 Profile 的每一个 `true` 副作用取得明确授权。

# Handoff Adapter Capability Profile v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已验证 Handoff Envelope 之后、任何 Adapter 选择或真实 dispatch 之前

## 目的

Adapter Capability Profile 是对一个候选 Handoff Adapter 的机器可读说明，不是 Adapter 实现、运行配置或权限凭据。它把渠道能力与副作用从 provider-neutral Handoff Envelope 中分离，避免仅凭“可交付”就推导网络、进程、通知、外部写入、费用或生产数据权限。

结构契约位于 `schemas/handoff-adapter-profile-v0.yaml`。本轮的合成 Profile 描述一个“本地文件候选”以验证契约，但仓库没有实现或调用对应 Adapter。

## 必须声明的能力

- 稳定 Profile ID、创建时间、可读名称、状态、审查时间、审查者引用和接收者类型；
- delivery mode 与 receipt mode；
- 是否支持幂等及幂等键来源；
- 无重试或有界重试，以及最多尝试次数；
- 最高可接受数据分类、个人数据策略和密钥策略；
- 是否可能产生费用及 dispatch 前披露要求；
- 七类副作用：本地文件写入、网络访问、启动进程、发送通知、修改外部服务、产生费用、访问生产数据；
- 选择确认、dispatch 确认和逐项副作用授权要求；
- Profile 自身不得包含密钥。

## 业务不变量

进入选择提案的 Profile 必须为 `reviewed`，并带有不早于 Profile 创建时间的审查时间与非敏感审查者引用。每一个值为 `true` 的副作用都必须且只能出现在 `required_effect_authorizations` 中，避免隐式授权或无效授权项。

此外：

- 支持幂等时必须声明实际键来源；不支持时键来源只能是 `not_applicable`；
- `retry.mode: none` 只能尝试一次；`bounded` 至少两次且最多五次；
- 已审查 Profile 不能使用 `receipt_mode: none`；
- 费用策略必须与 `cost_incurred` 副作用一致，可能产生费用时必须要求 dispatch 前披露；
- Profile 的最高数据分类不得低于待选 Envelope 的分类。

这些校验只能证明声明内部一致，不能证明真实 Adapter 按声明运行。真实实现仍需要 adapter-specific contract test、失败清理、回执核验、幂等/重试演练和渠道授权。

## 隐私边界

现有 Handoff Envelope 只提供整个封装的数据分类；Confirmation Receipt 的个人数据和密钥声明只覆盖确认原文，不覆盖内嵌 Prompt Package。因此 Profile 可以声明自己的数据策略，但不能据此断言 Envelope 的个人数据或密钥兼容性。

选择文案必须把这两项显示为未知。用户确认选择后，必须运行 [Handoff Payload Data Attestation v0](handoff-payload-data-attestation-v0.md) 审核完整 Envelope payload；禁止把 `data_classification` 兼容或选择确认写成“全部数据策略已通过”。Profile v0 不声明 retention/export/purpose 策略，Attestation v0 也不得宣称这些维度兼容。

## 副作用边界

Schema、Fixture 和选择预演均不会读取凭据、连接平台、启动进程、写文件、发送通知、产生费用或修改外部服务。Profile 中的 `true` 只表示“未来实现若 dispatch 会产生此效果并需要授权”，不表示效果已获批准或已经发生。

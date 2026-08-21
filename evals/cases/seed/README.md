# Seed Cases v0

本目录包含 10 个合成、尚未运行的 PMind Validation Sprint 案例。每个文件遵循 `evals/schema/case-v0.yaml`。

## 使用规则

- `intent.raw_intent` 是基线组唯一的产品输入，不得改写。
- `oracle` 只供案例主持人回答实际提出的 Clarification，并供评审者在运行后评分。PMind 操作者和两个实验组的 Downstream Executor 都不得提前读取。
- `run_records: []` 表示尚未执行，不是缺失数据；运行后只追加符合 Case Schema `0.2.0` 的真实记录。
- 每条运行记录必须固定 Executor Profile、执行器/模型/推理设置、Workspace Set 收据摘要、工作区前后 revision、返工轮次、分段耗时、成本和协议偏差；未知成本不得伪造为 0。
- 每条运行记录必须对应同一 `evals/runs/<run_id>/` 下的 `input.md`、`result.md`、`acceptance.yaml`、`executor-profile.yaml` 和 `workspace-set.yaml`；后两份冻结收据的文件 SHA-256 必须与记录一致，验收文件遵循 `evals/schema/acceptance-result-v0.yaml`。
- `acceptance.yaml` 保存两名独立评审的原始判断；分歧时只能保持 `needs_adjudication`，或由与两名评审均不同的第三人转为 `adjudicated`。
- 每组使用隔离工作区，执行器不得读取本目录。
- 任何案例含有的敏感或高风险场景都是测试设定，不构成真实操作授权。

## 覆盖

| Case | 任务 | 主要风险/缺口 |
| --- | --- | --- |
| `seed-001` | CSV 导出 | 范围、隐私、验收 |
| `seed-002` | 团队角色权限 | 授权、兼容、安全 |
| `seed-003` | 订阅按比例退款 | 财务逻辑、精度、审批 |
| `seed-004` | 通知设置迁移 | 数据迁移、回滚 |
| `seed-005` | CRM Webhook | 外部 API、重试、幂等 |
| `seed-006` | 前端框架选型 | 当前证据、供应链、约束 |
| `seed-007` | 竞品分析 | 证据时效、比较口径 |
| `seed-008` | 批量删除项目 | 破坏性动作、恢复、审批 |
| `seed-009` | AI 客服知识库 | 隐私、注入、引用 |
| `seed-010` | 多语言无障碍引导 | 用户场景、无障碍、可测试性 |

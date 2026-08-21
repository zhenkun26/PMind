# Seed Calibration

本目录保存种子案例校准 Wave 的就绪清单，不保存伪造的实验结果。首批 Wave 为 `wave-01.yaml`，选择：

- `seed-001`：编码 Handoff，覆盖隐私、授权和大数据量；
- `seed-006`：技术选型，覆盖现状证据、供应链和 Handoff 边界；
- `seed-009`：AI 产品探索，覆盖租户隔离、提示注入和引用。

三例横跨 `coding_handoff`、`technical_selection` 和 `product_exploration`，用于先校准流程与 Rubric，不用于估算 PMind 的产品效果。

## 为什么当前是 `blocked`

当前会话只有一名操作者，且三例都缺少可隔离的 Downstream Executor Fixture。此时直接生成 baseline、PMind 输出并自行评分会泄露 oracle、混淆角色并把模拟结果误写成产品证据。

`blocked` 是 Quality Gate 的正确结果，不是执行失败。它阻止新增 `run_records`，但不阻止继续准备 Fixture 和角色。

## 启动条件

只有 `wave-01.yaml` 同时满足以下条件，才能把 `can_start` 改为 `true`：

1. 四个角色均为 `assigned`，角色合并偏差已记录；
2. 三个 Fixture 均为 `ready`，并记录同一只读 base revision；
3. Downstream Executor 的类型、模型版本、推理设置、工具策略和时限已冻结；
4. baseline 与 PMind 分别拥有隔离工作区，无法读取 `oracle` 或另一组结果；
5. Contract validator 通过，Rubric 版本未在看到结果后改变；
6. `blocked_reasons` 为空，所有 `start_gates` 为 `true`。

仓库验证器会拒绝自相矛盾的就绪状态，例如 `can_start: true` 但仍存在未分配角色或缺失 Fixture。

## 推荐执行顺序

1. 创建三个最小 Fixture，只包含验证 Acceptance Criteria 所需的代码、合成数据和接口；不使用生产数据。
2. 为每个 Fixture 冻结 base revision，并为两组复制隔离工作区。
3. 分配角色和冻结执行器配置，然后运行 `ruby scripts/validate_evals.rb`。
4. 按清单中的 `arm_order` 运行；主持人只回答实际提出的问题。
5. 两名评审独立评分前三例，记录原始分歧和一致率。
6. 若 Rubric 可一致使用，再准备剩余七例；若不可一致，提升协议版本后重跑受影响案例。

## 不属于本 Wave 的动作

- 不安装 Agent SDK、Promptfoo、模型客户端或数据库；
- 不调用真实支付、CRM、知识库或生产数据；
- 不把单人非盲 dry-run 记为 First-pass Delivery Success；
- 不因为三例结果提前作商业化或技术栈结论。

# Calibration Readiness Copy v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: current `CalibrationPreflight::Result`

## 目的

本契约把机器 preflight 的六门禁结果投影为安全、克制、可直接交给校准操作者的 Markdown。它不解析或回显自由文本 blocker，不修改 Wave/Profile/workspace，不分配角色，也不替用户选择执行器配置。

入口为 `scripts/render_calibration_readiness_copy.rb`。默认运行当前仓库 Wave；可用 `--workspace-set ABSOLUTE_PATH` 只读验证已经准备的外部 workspace set。提交路径只用于 preflight，不出现在文案中。

## blocked 文案矩阵

`blocked` 是合法产品状态，renderer 返回成功并展示：

1. 标题 **校准尚未就绪**；
2. 真实通过数，例如当前 `3/6`；
3. 已通过 gate 的安全标签；
4. 按门禁顺序最多三组缺失输入；
5. 明确禁止启动、写 `run_records`、安排盲评或报告 First-pass Delivery Success 的停止条件。

三组真实输入形成后，文案要求基于重新计算的证据同步 Wave `start_gates/status/can_start/blocked_reasons`，禁止为了通过 preflight 预先置绿。若六个 gate 本身都已有证据但 manifest 尚未对齐，blocked 文案会给出一条 manifest 一致性动作，而不是空白清单。

缺失输入只按 gate 派生：

- `roles_assigned=false`：请求四个互异的本地 opaque ID，并禁止姓名、邮箱等非必要个人信息；
- `executor_frozen=false`：请求执行器/模型/推理/工具与网络/时限/尝试次数六类真实决策，并要求两臂一致；
- `isolated_workspaces_ready=false`：要求 Profile 冻结后在仓库外准备和验证六个不含 oracle、彼此隔离的工作区。

已通过的 gate 不再提问。当前 workspace set 验证通过时，文案从三组自动收敛为两组；无效 workspace 仍展示同一安全行动，不回显提交路径或内部错误。

## ready 文案矩阵

全部 `6/6` 时标题为 **校准启动门禁已通过**，只允许进入冻结的三案例协议，并复述四角色分离、同一 Profile、arm isolation、禁 oracle/改 Rubric/外部写入/生产数据/秘密和真实双评审边界。

ready 只表示可以开始，不表示任何案例、产品效果或商业化目标已通过。

## 安全输出

文案不得包含：

- assignee ref 或人员身份；
- Executor Profile 的具体值；
- workspace 绝对路径；
- preflight 原始 blocker 或内部异常；
- Fixture oracle、运行结果、Acceptance Result 或虚构效果。

renderer 只读调用 preflight。仓库结构/Schema 失效属于错误并返回 `1`；blocked/ready 都是可展示结果并返回 `0`。

## 命令

```sh
ruby scripts/render_calibration_readiness_copy.rb
ruby scripts/render_calibration_readiness_copy.rb --workspace-set /absolute/path/calibration-001
```

本能力把协作阻断变为最小输入清单，但不能自行解除任何门禁。真实推进仍需四个不同参与者、六项 Executor 决策和仓库外 workspace evidence。

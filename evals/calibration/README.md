# Seed Calibration

本目录保存种子案例校准 Wave 的就绪清单，不保存伪造的实验结果。首批 Wave 为 `wave-01.yaml`，选择：

- `seed-001`：编码 Handoff，覆盖隐私、授权和大数据量；
- `seed-006`：技术选型，覆盖现状证据、供应链和 Handoff 边界；
- `seed-009`：AI 产品探索，覆盖租户隔离、提示注入和引用。

三例横跨 `coding_handoff`、`technical_selection` 和 `product_exploration`，用于先校准流程与 Rubric，不用于估算 PMind 的产品效果。

## 当前状态：`ready`，尚未运行

三个最小 Fixture 已创建并冻结 workspace digest。用户已确认四个角色由四名不同的真实参与者承担，身份映射在线下保管；仓库只保存四个 assignment-scoped opaque refs。Executor Profile 已冻结为精确 Codex CLI 版本和二进制摘要、已实际响应的 `gpt-5.6-terra` 标识、standard/medium、禁网和 arm-only 工具策略、每臂 30 分钟及一次计分尝试。

六个 baseline/PMind 副本已在获批的仓库外路径生成并通过独立验证，`oracle_included=false`。向 preflight 提交该 exact workspace set 时，六个启动门禁全部通过；未提交路径时仍应返回 5/6 blocked，因为仓库内的 ready 声明不能代替当前进程对外部证据的复验。

进一步的本机探测确认：复制隔离与 Runtime Arm Isolation 不是同一件事。冻结 CLI 的普通 `workspace-write`/广域只读配置仍可读取 sibling arm；最小 named permission profile 可在 `codex sandbox` shell probe 中拒绝 sibling arm，但当前冻结 CLI 尚无已验证的 `codex exec` 端到端应用路径。因此 Workspace Set 层仍为 6/6 ready，计分启动保持 blocked，直到实际 Codex launch path 用同一配置证明当前 arm 可读写且仓库、oracle、其他五个 arm 不可读。

运行记账契约也已准备完成：Case Schema `0.2.0` 固定模型、Profile、Workspace Set、工作区 revision、返工和耗时证据，Acceptance Result Schema `0.1.0` 强制双评审与三态裁决。仓库验证器会核对运行目录、成功公式和最终运行结论。

当前 `ready` 只授权按冻结 Runbook 启动三案例 Wave。它不是任何案例 PASS、First-pass Delivery Success、商业化结论或生产 Adapter 授权；在真实两臂输出和双评审结果存在前，`run_records` 与 Acceptance Result 仍为空。

## 启动条件

只有 `wave-01.yaml` 同时满足以下条件，才能把 `can_start` 改为 `true`：

1. 四个角色均为 `assigned` 且引用互异；角色合并只能记录为偏差，不能通过本 Wave 的盲评启动门禁；
2. 三个 Fixture 均为 `ready`，并记录同一只读 base revision；
3. Downstream Executor 的产品/版本、模型版本、推理设置、工具策略、时限和尝试次数已冻结，并记录 Profile 摘要；
4. baseline 与 PMind 分别拥有隔离工作区，无法读取 `oracle` 或另一组结果；
5. Contract validator 通过，Rubric 版本未在看到结果后改变；
6. `blocked_reasons` 为空，所有 `start_gates` 为 `true`。

仓库验证器会拒绝自相矛盾的就绪状态，例如 `can_start: true` 但仍存在未分配角色或缺失 Fixture。

## 推荐执行顺序

1. ~~创建三个最小 Fixture，并冻结 base revision。~~ 已完成，见 `evals/fixtures/`。
2. 在 `evals/calibration/executor-profiles/calibration-001.yaml` 填写真实执行器决策，按同目录 README 冻结摘要；为四个角色写入互异 opaque ID。
3. 执行器冻结后，使用下方准备器在仓库外从对应 workspace digest 创建 baseline 与 PMind 副本；两组都排除 `oracle/`：

   ```sh
   ruby scripts/prepare_calibration_workspaces.rb --output /absolute/path/calibration-001
   ruby scripts/prepare_calibration_workspaces.rb --verify /absolute/path/calibration-001
   ```

   准备器拒绝相对路径、仓库内路径和已存在目标，输出 `workspace-set.yaml` 收据。每个 Downstream Executor 仍必须被沙箱限制在自己的 arm 目录；文件复制本身不是操作系统级沙箱。

4. 运行统一 preflight；只有输出 `READY` 才能启动：

   ```sh
   ruby scripts/calibration_preflight.rb --workspace-set /absolute/path/calibration-001
   ```

   使用仓库统一状态入口时，通过任务专用环境变量提交同一证据：

   ```sh
   PMIND_CALIBRATION_WORKSPACE_SET=/absolute/path/calibration-001 rake status
   ```

   需要交给角色协调者时，使用安全文案 renderer；它不会回显 workspace 路径、人员引用或配置值：

   ```sh
   ruby scripts/render_calibration_readiness_copy.rb --workspace-set /absolute/path/calibration-001
   ```

   renderer 的 blocked 输出是可展示结果，不会解除任何 gate；原 preflight 的 `READY` 只允许进入角色协调与 Runtime Arm Isolation 准备，不能单独授权计分启动。

   为四个真实参与者生成最小披露 Briefing 时，使用只读 role renderer：

   ```sh
   ruby scripts/render_calibration_role_briefing.rb \
     --workspace-set /absolute/path/calibration-001 \
     --role facilitator
   ```

   可用角色为 `facilitator`、`pmind_operator`、`reviewer_1`、`reviewer_2`。它不会写 packet、运行模型或启动 arm。当前主持人文案会明确显示 Runtime Arm Isolation 尚无端到端证据，因此不得把 Briefing 当作计分启动授权。

5. 先对实际 Codex launch path 完成 Runtime Arm Isolation probe；在探测与计分运行使用同一权限配置前，不得启动。通过后才按清单中的 `arm_order` 运行；主持人只回答实际提出的问题。
6. 两名评审独立评分前三例，按 `consensus` / `needs_adjudication` / `adjudicated` 保存原始分歧和一致率；没有独立第三评审时，分歧结果保持未计分。
7. 若 Rubric 可一致使用，再准备剩余七例；若不可一致，提升协议版本后重跑受影响案例。

## 不属于本 Wave 的动作

- 不安装 Agent SDK、Promptfoo、模型客户端或数据库；
- 不调用真实支付、CRM、知识库或生产数据；
- 不把单人非盲 dry-run 记为 First-pass Delivery Success；
- 不因为三例结果提前作商业化或技术栈结论。

# Clarification Revision Proposal v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已通过 Answer Receipt dry-run 的回答归一化与 Session revision 预演

## 目的

Revision Proposal 把“用户逐字回答”与“PMind 准备如何理解并更新 Session”分开。它描述一个尚未应用的 delta，在内存中生成候选 Session 并运行完整校验，然后要求用户确认文案中的理解。

参考实现位于 `scripts/preview_clarification_revision.rb`。它不写回 Session，不替用户确认，不调用模型，也不授予高风险动作。

## 三层事实边界

1. **Answer Receipt**：用户实际说了什么；逐字保存，不归一化。
2. **Revision Proposal**：操作者/模型准备如何理解；属于待确认提案，不是事实。
3. **Candidate Session**：把 Proposal delta 应用到内存副本后的候选状态；只有结构和业务规则通过，不代表用户已确认或磁盘状态已改变。

任何一层都不能覆盖上一层。Proposal 只引用原答摘要；候选 round 的 `user_answer` 必须由 Receipt 原文注入，不能由 Proposal 提供。

## Delta 结构

机器结构位于 `schemas/clarification-revision-proposal-v0.yaml`。Proposal 绑定：

- 当前 Session ID、raw Intent 摘要和源状态；
- Answer Receipt ID 和连续轮次；
- `confirmation.required: true`、`status: pending`；
- `high_risk_authorization_inferred: false`。

`patch` 包含：

- `status_after`；
- 本轮问题从 `pending` 到 `asked` 的更新；
- 下一轮新增问题（如仍需 Clarification）；
- 仅追加的一轮及每项归一化结果；
- 本轮涉及 gap 的更新；
- 允许移除的旧 assumption/unknown ID；
- 新增 assumptions、unknowns 和 decisions；
- 完整的 `compile_gate_after`。

## 允许的状态转换

| 源状态 | 候选状态 | 条件 |
| --- | --- | --- |
| `gap_scan` | `clarifying` | 本轮后仍有 1–3 个最高优先级问题 |
| `gap_scan` | `ready_to_compile` | 无阻塞 gap/unknown/冲突，高风险动作已标记 Approval Point |
| `gap_scan` | `blocked` | 存在不可安全默认的阻塞或冲突 |
| `clarifying` | `clarifying` | 继续下一连续轮且轮数政策满足 |
| `clarifying` | `ready_to_compile` | 满足全部 Compile Gate 停止条件 |
| `clarifying` | `blocked` | 新回答暴露不可安全继续的阻塞 |

不允许回到 `intake` / `gap_scan`。Candidate Session 必须通过 Clarification Session v0 的全部状态、优先级、引用、轮次和风险检查。

## Append-only 与可变范围

- Session ID、创建时间、语言、Intake 和 round policy 不变。
- 历史问题和历史轮次逐字段不变。
- Receipt 覆盖的问题必须按原顺序更新为本轮 `asked`；新 round 的原答只来自 Receipt。
- 只能更新本轮问题所属的 gap dimension。
- 旧 assumption/unknown 只有在它是被更新 gap 当前的 `knowledge_ref` 时才可移除。
- 未列入移除项的既有 knowledge 和全部既有 decision 必须保留；新增项只能追加。
- 既有高风险动作不得删除或改写；可以新增仍为 `approval_point_required: true` 的动作。

这些规则只限制 revision 的来源和范围；归一化结论是否正确仍需用户确认。

## Outcome 规则

| Receipt 类型 | 允许的归一化 outcome |
| --- | --- |
| `answered` | `resolved`、`assumed`、`unknown` |
| `skipped` | `assumed`、`unknown` |
| `unknown` | `unknown` |
| `refused` | `refused` |

`resolved` gap 不阻塞且没有 knowledge ref；`assumed` 必须引用 Assumption；`unknown/refused` 形成 unknown gap，并遵守关键维度必须阻塞的规则。普通回答不能成为 Approval Point 的批准证据。

## 用户确认文案

stdout 首先明确“请确认我对本轮回答的理解”和“Session 尚未修改”。每题只展示：

- 原问题；
- 拟归一化结论；
- 用户可理解的产品影响；
- `已解决` / `暂按假设` / `仍未知` / `拒绝提供` 标签。

随后披露候选状态、新增假设、仍未知项、新增决策和全部高风险审批边界。不得展示原答、摘要、内部 ID、字段路径、source refs、priority 或 decision maker ref。所有动态文本使用共享 Markdown 安全层。

结尾固定提供三种选择：

1. 确认：允许后续步骤据此创建新 revision；
2. 修改：指出哪一项理解或影响不准确；
3. 拒绝：保留当前 Session，不应用 Proposal。

本 CLI 不接收或保存该选择。后续选择必须按 [Clarification Confirmation Receipt v0](clarification-confirmation-receipt-v0.md) 独立保存并绑定当前三份精确输入文件。

## 命令与退出码

```sh
ruby scripts/preview_clarification_revision.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml
```

- `0`：三份输入有效，delta 可生成有效 Candidate Session，确认文案写入 stdout；
- `1`：绑定、delta 或 Candidate Session 无效，仅在 stderr 返回不含原答的错误。

成功不表示用户已确认、Session 已更新、Prompt Package 已生成或风险已授权。

用户作出选择后，先运行 `ruby scripts/preview_clarification_confirmation.rb SESSION RECEIPT PROPOSAL CONFIRMATION`。只有有效的 `confirmed` Receipt 才能交给 no-overwrite revision 创建命令。

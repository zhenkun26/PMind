# Clarification Answer Receipt v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 当前 Clarification 问题轮次的用户原答收据与只读适用性预演

## 目的

Answer Receipt 在用户回答与 Session 状态更新之间建立一道可审计边界。它逐字保存本轮原答并绑定当前问题，但不包含归一化结论、gap 变更、决策推断或授权结果。

只读参考实现位于 `scripts/preview_clarification_answers.rb`。命令只判断 Receipt 是否适用于当前 Session，并生成“已收到、尚未应用”的用户确认文案；它不会写回 Session。

## Receipt 结构

机器可读结构位于 `schemas/clarification-answer-receipt-v0.yaml`。顶层必须包含：

- 稳定 `receipt_id`；
- 目标 `session_id` 和不可变 `session_raw_intent_sha256`；
- 捕获时的 `session_status` 与待追加 `round_number`；
- 带时区的 `captured_at`；
- 语言、数据分类、个人数据和 secrets 声明；
- 按当前问题顺序排列的 1–3 条 `responses`。

每条 Response 必须包含：

- `question_id`；
- 当前问题原文的 `question_sha256`；
- `response_kind`：`answered`、`skipped`、`unknown` 或 `refused`；
- 逐字 `user_answer` 及其 `user_answer_sha256`。

Receipt 不得包含 `normalized_conclusion`、`outcome_status`、受影响字段、gap 状态或 Approval Point。那些内容必须在人工/受控归一化步骤中根据原答另行生成和复核。

## 状态适用性

| 当前 Session 状态 | Dry-run 结果 | 原因 |
| --- | --- | --- |
| `gap_scan` | 允许预演第 1 轮 | 已有完整 gap map 和首轮问题 |
| `clarifying` | 允许预演下一连续轮 | 已有历史轮次和下一问题 |
| `intake` | 拒绝 | 尚未形成问题轮次 |
| `ready_to_compile` | 拒绝 | 已满足停止条件，不应补录新一轮 |
| `blocked` | 拒绝 | 必须先按阻塞原因恢复到可追问状态 |

Receipt 的 Response ID 必须与 `compile_gate.next_question_ids` 完全相同、顺序一致。每个问题的摘要必须匹配当前问题原文；`round_number` 必须等于已有轮数加一。这样可以拒绝旧页面重放、漏答、夹带问题和错轮应用。

## 时间与数据边界

- `captured_at` 不得早于 Session 创建时间或最后一轮完成时间。
- Receipt 数据分类不得低于 Session Intake 的分类。
- `contains_personal_data: true` 时不得使用 `public` 分类。
- `contains_secrets` 固定为 `false`；发现密钥或 token 时应停止捕获并要求用户撤回/轮换，不得保存到 Receipt。
- 每条原答最多 4000 个字符；更长内容应先最小化到本轮决策真正需要的信息。

Schema 与摘要校验只能发现声明或内容漂移，不能证明用户身份、事实正确性或文本中绝对不存在秘密。

## 用户确认文案

Dry-run 成功后，stdout 使用以下信息层级：

1. 标题明确“回答已收到，尚未应用”；
2. 说明收到几项，以及目标轮次；
3. 逐题显示问题和记录状态，但不回显 `user_answer`；
4. 说明下一步仍需归一化、影响字段/信息缺口复核和 Session 新 revision；
5. 明确普通回答不能自动成为高风险授权。

Response 状态文案：

| `response_kind` | 用户文案 |
| --- | --- |
| `answered` | 已收到回答，等待归一化与复核 |
| `skipped` | 已记录跳过，将按安全默认或停止条件处理 |
| `unknown` | 已记录“不知道”，将重新判断是否阻塞 |
| `refused` | 已记录拒绝提供，不会推断或补写 |

确认文案不得展示原始 Intent、原答、摘要、内部 ID、优先级、source refs 或归一化结论。所有动态问题文本必须折叠为单行并转义 HTML/Markdown。

## 命令与退出码

```sh
ruby scripts/preview_clarification_answers.rb path/to/session.yaml path/to/receipt.yaml
```

- `0`：两个文档有效、绑定关系一致，完整确认文案写入 stdout；
- `1`：任一文档不可读、无效或已过期，仅在 stderr 返回不含原答的错误。

成功只表示 Receipt 可进入后续人工/受控应用步骤，不表示答案已归一化、Session 已改变、风险已批准或 Prompt Package 已生成。

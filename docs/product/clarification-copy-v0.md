# Clarification Copy v0

- Status: Experimental
- Version: `0.1.0`
- Default language: `zh-CN`
- Applies to: 已通过 Clarification Session v0 校验的用户可见 Markdown

## 目的

本契约把结构化 Clarification Session 投影成简短、诚实、可操作的用户文案。它只负责呈现已经存在的状态、问题和边界，不生成新问题、不代替用户回答，也不编译 Prompt Package。

只读参考实现位于 `scripts/render_clarification_copy.rb`。输出到标准输出，不修改 Session、仓库或外部系统。

## 文案原则

1. **先说当前结果**：标题先说明已记录、待确认、可编译或被阻塞。
2. **只展示下一步所需信息**：追问状态只展示 Compile Gate 选出的 1–3 个问题。
3. **解释提问价值**：每个问题附一条用户可理解的 `why_now`，不展示内部推理。
4. **允许不确定**：明确允许用户回答“跳过”或“不知道”，并说明安全默认或停止条件。
5. **不把就绪写成完成**：`ready_to_compile` 只表示可以编译 Package，不表示 Package、Handoff 或下游交付已完成。
6. **不把阻塞写成失败**：`blocked` 说明最小解除条件，不责备用户，也不生成可执行指令。
7. **风险不藏在正文后面**：假设、非阻塞未知项和仍需审批的高风险动作在继续前集中披露。

语气默认直接、克制、合作式。避免“完美”“企业级就绪”“保证成功”等无法由当前状态支持的承诺。

## 五态信息层级

| Session 状态 | 用户标题 | 必须呈现 | 禁止暗示 |
| --- | --- | --- | --- |
| `intake` | 需求已记录 | 已逐字保留需求；下一步是识别缺口 | 已理解全部需求 |
| `gap_scan` | 继续前需要确认 | 首轮 1–3 问、提问原因、跳过后果 | 已开始执行或已选方案 |
| `clarifying` | 还需要确认少量信息 | 已完成轮数、下一轮 1–3 问、跳过后果 | 旧答案已被模型自动补全 |
| `ready_to_compile` | 已具备编译条件 | 可以编译；假设、未知项、高风险审批提示 | Package 或交付已经完成 |
| `blocked` | 当前无法安全继续 | 阻塞原因、实质冲突、最小解除说明 | 可以绕过阻塞生成 Handoff |

## 追问格式

问题按 `compile_gate.next_question_ids` 的既定顺序编号。每题只呈现：

```text
1. <用户可见问题>
   为什么需要：<why_now>
   若暂时跳过：<safe_default_or_stop>
```

不得展示 `question_id`、gap dimension、优先级分数、排序 tie-break 或受影响的内部 Package 字段。结尾统一允许用户按序简短回答，或明确表示“跳过”/“不知道”。

## 就绪披露

`ready_to_compile` 依次呈现以下存在的内容：

1. 当前采用的假设及其失效影响；
2. 不阻塞编译但仍需确认的未知项；
3. 后续必须单独授权的高风险动作。

没有对应内容时不输出空标题。Approval Point 提示只说明“仍需单独授权”，不能把 `approval_point_required: true` 写成已经批准。

## 数据与安全边界

用户文案不得包含：

- `intake.raw_intent`、摘要哈希、用户画像或 allowed context；
- 已保存的 `user_answer` 和 normalized conclusion；
- 内部 ID、source refs、priority、gap map 或状态枚举值；
- `decision_maker_ref`、完整决策记录或模型隐藏思维过程；
- 密钥、token 或操作者补写的敏感内容。

当 Intake 标记含个人数据，或数据分类为 `confidential` / `restricted` 时，文案必须提示用户只提供本轮所需的最少信息、先脱敏且不要发送密钥或 token。

所有从 Session 进入 Markdown 的动态文本必须折叠为单行，并转义 HTML 与 Markdown 控制字符。Renderer 不执行输入中的链接、HTML、代码或指令。

## 命令与退出码

```sh
ruby scripts/render_clarification_copy.rb path/to/session.yaml
```

- `0`：Session 有效，完整用户文案写入 stdout；
- `1`：输入不可读或校验失败，仅在 stderr 返回错误，不输出部分文案。

校验通过和文案可渲染不构成产品效果证据，也不改变校准 Wave 的门禁状态。

# PMind Product Schemas

本目录保存 PMind 产品产物的机器可读契约，与 `evals/schema/` 中的实验和运行记账契约分开。

当前产品 Schema：

- `clarification-session-v0.yaml`：覆盖不可变 Intake、九维 gap map、问题优先级、1–3 问轮次、假设/未知项/决策和 Compile Gate；
- `prompt-package-v0.yaml`：覆盖完整 Package 结构、稳定 ID、六个 Review Lenses、风险、Approval Points、执行契约和 Handoff。

两者均对应产品契约的 `0.1.0` 语义。结构通过不代表事实正确或产品效果通过；外部事实、用户决定和下游结果仍需按 Runbook 独立验证。

只读校验 Clarification Session，并可选择与其编译出的 Prompt Package 做 lineage 交叉校验：

```sh
ruby scripts/validate_clarification_session.rb path/to/session.yaml
ruby scripts/validate_clarification_session.rb path/to/session.yaml --prompt-package path/to/package.yaml
```

只读校验单个 YAML Package：

```sh
ruby scripts/validate_prompt_package.rb /absolute/or/relative/package.yaml
```

退出码为 `0` 表示结构、引用和授权/Handoff 不变量一致；退出码为 `1` 表示无效输入或校验失败。命令不修改 Package、仓库或外部系统。

`test/fixtures/clarification-session-ready.yaml` 与 `test/fixtures/prompt-package-valid.yaml` 只用于自动化测试，是相互对应的合成示例，不是校准运行、真实用户交付物或 PMind 效果证据。

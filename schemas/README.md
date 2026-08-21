# PMind Product Schemas

本目录保存 PMind 产品产物的机器可读契约，与 `evals/schema/` 中的实验和运行记账契约分开。

当前产品 Schema：

- `clarification-answer-receipt-v0.yaml`：覆盖当前问题轮次的逐字原答、问题/回答摘要、数据分类和 Session 绑定；
- `clarification-confirmation-receipt-v0.yaml`：覆盖用户对精确 Session/Receipt/Proposal 文件的确认、修改或拒绝选择；
- `clarification-revision-proposal-v0.yaml`：覆盖答案归一化、gap/知识项变更、候选状态、Compile Gate 和三文件绑定；
- `clarification-session-v0.yaml`：覆盖不可变 Intake、九维 gap map、问题优先级、1–3 问轮次、假设/未知项/决策、Compile Gate 和可选 revision lineage；
- `handoff-confirmation-receipt-v0.yaml`：覆盖用户对精确六文件 Handoff Proposal 链的确认、修改或拒绝选择、个人数据声明及显式 Handoff 授权边界；
- `handoff-proposal-v0.yaml`：覆盖已验证最终 Package 的精确文件摘要、交接对象、pending confirmation 和零 Handoff/外部效果授权边界；
- `prompt-package-compilation-confirmation-receipt-v0.yaml`：覆盖用户对精确 Session revision、候选 Package 和 Compilation Proposal 的确认、修改或拒绝选择；
- `prompt-package-compilation-proposal-v0.yaml`：覆盖 ready Session revision、候选 Package、精确文件摘要、pending confirmation 和零授权边界；
- `prompt-package-v0.yaml`：覆盖完整 Package 结构、稳定 ID、六个 Review Lenses、风险、Approval Points、执行契约、可选确认创建 lineage 和 Handoff。

九者均对应产品契约的 `0.1.0` 语义。结构通过不代表事实正确或产品效果通过；外部事实、用户决定和下游结果仍需按 Runbook 独立验证。

只读预演 Answer Receipt 是否适用于当前 Session，并生成不回显原答的确认文案：

```sh
ruby scripts/preview_clarification_answers.rb path/to/session.yaml path/to/receipt.yaml
```

只读校验 Revision Proposal、在内存应用 delta、复验候选 Session，并生成不回显原答的用户确认文案：

```sh
ruby scripts/preview_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml
```

只读校验 Confirmation Receipt 与三个精确来源文件，并按明确确认创建不覆盖原文件的新 Session revision：

```sh
ruby scripts/preview_clarification_confirmation.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml
ruby scripts/create_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

只读重放四份已确认来源并核对已持久化 revision 的完整 lineage 与 Session 内容：

```sh
ruby scripts/verify_clarification_revision_lineage.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

只读校验 ready Session revision、候选 Package 与 Compilation Proposal 的精确绑定，并生成待确认审阅文案：

```sh
ruby scripts/preview_prompt_package_compilation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml
```

只读校验 Compilation Confirmation Receipt 与三份精确来源文件，并生成不回显用户确认原文的结果文案：

```sh
ruby scripts/preview_prompt_package_compilation_confirmation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml
```

重跑完整确认链，并只在 confirmed + Handoff-ready + creation-authorized 时，以 `0600` 权限创建不覆盖任何来源的最终 Package：

```sh
ruby scripts/create_prompt_package.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml
```

只读重放四份已确认来源，并逐字段核对 persisted final Package 的 `compilation` metadata 与完整业务内容：

```sh
ruby scripts/verify_prompt_package_lineage.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml
```

只读重放完整最终 Package 来源链，再校验精确文件摘要绑定的 pending Handoff Proposal，并展示交接边界和三种选择：

```sh
ruby scripts/preview_handoff_proposal.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml path/to/handoff-proposal.yaml
```

只读重放六文件 Handoff Proposal 链，再校验用户选择、六份来源摘要和显式 Handoff 授权状态：

```sh
ruby scripts/preview_handoff_confirmation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml path/to/handoff-proposal.yaml path/to/handoff-confirmation.yaml
```

只读校验 Clarification Session，并可选择与其编译出的 Prompt Package 做 lineage 交叉校验：

```sh
ruby scripts/validate_clarification_session.rb path/to/session.yaml
ruby scripts/validate_clarification_session.rb path/to/session.yaml --prompt-package path/to/package.yaml
```

只读校验单个 YAML Package：

```sh
ruby scripts/validate_prompt_package.rb /absolute/or/relative/package.yaml
```

退出码为 `0` 表示对应契约成立；退出码为 `1` 表示无效输入、过期确认、未授权创建、lineage 漂移或写入失败。`create_clarification_revision.rb` 与 `create_prompt_package.rb` 只创建用户指定的新文件，其余命令不修改输入、仓库或外部系统；两个创建命令都永不覆盖已有路径。Compilation Proposal/Confirmation Preview 的成功不创建最终 Package；Creator、lineage verifier 或 Handoff Proposal Preview 的成功不授权 Handoff。Handoff Confirmation Preview 可以验证显式授权已成立，但仍不执行 Handoff 或授权外部效果。

`test/fixtures/` 下的 Clarification Session、Answer Receipt、Revision Proposal、Confirmation Receipt、Compilation Proposal、Compilation Confirmation Receipt、Handoff Proposal、Handoff Confirmation Receipt 与 Prompt Package 只用于自动化测试，是合成示例，不是校准运行、真实用户交付物或 PMind 效果证据。

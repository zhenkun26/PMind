# PMind Product Schemas

本目录保存 PMind 产品产物的机器可读契约，与 `evals/schema/` 中的实验和运行记账契约分开。

当前 `prompt-package-v0.yaml` 对应 `docs/product/prompt-package-v0.md` 的 `0.1.0` 语义，覆盖完整 Package 结构、稳定 ID、六个 Review Lenses、风险、Approval Points、执行契约和 Handoff。结构通过不代表事实正确或产品效果通过；外部事实、用户决定和下游结果仍需按 Runbook 独立验证。

只读校验单个 YAML Package：

```sh
ruby scripts/validate_prompt_package.rb /absolute/or/relative/package.yaml
```

退出码为 `0` 表示结构、引用和授权/Handoff 不变量一致；退出码为 `1` 表示无效输入或校验失败。命令不修改 Package、仓库或外部系统。

`test/fixtures/prompt-package-valid.yaml` 只用于自动化测试，是合成示例，不是校准运行、真实用户交付物或 PMind 效果证据。

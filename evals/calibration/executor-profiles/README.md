# Executor Profiles

`calibration-001.yaml` 是首个校准 Wave 的单一执行器事实来源。`draft`
状态允许真实缺项，但 `unresolved_fields` 必须与未填写的决策字段精确一致；不得用
`latest`、`TBD`、空字符串或推测值伪装冻结。

冻结前必须明确：

- 执行器产品与版本、模型版本、推理设置；
- 两组完全相同的工具和网络策略；
- 单臂时限和最多尝试次数；
- `tool_policy` 对 workspace、oracle、另一实验臂、Git、依赖安装和外部写入的限制。

全部字段确定后，将 Profile 改为 `frozen`、清空 `unresolved_fields`，计算文件摘要：

```sh
ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' \
  evals/calibration/executor-profiles/calibration-001.yaml
```

把摘要写入 `wave-01.yaml` 的 `executor_config.profile_revision`，并把对应状态与
gate 改为 `frozen` / `true`。验证器会拒绝缺项、过期摘要或 Wave/Profile 状态不一致。

角色引用只使用本地、不含非必要个人信息的 opaque ID。四个校准角色必须是四个互异
引用；一人兼任时应保留 Wave 为 `blocked`，不能声称盲评已就绪。

当前 `calibration-001.yaml` 已按用户确认冻结：精确 Codex CLI 版本与二进制摘要、
`gpt-5.6-terra` 可用性探测、standard/medium、禁网与 arm-only 工具策略、每臂
30 分钟、一次计分尝试。可用性探测只证明该模型标识在探测时可响应，不是校准运行、
模型快照证明或产品效果证据；每个实验臂启动前仍须复核客户端摘要和有效模型配置。
Profile 中的 `arm_only` 是必须兑现的策略，不是提示词级事实。当前 Workspace Set 已
验证六份副本，但实际 `codex exec` launch path 尚未证明仓库、oracle 与其他 arm
不可读；在绑定同一 Profile 的 Runtime Arm Isolation probe 通过前不得启动计分臂。

# Calibration Fixtures

每个 Fixture 分成两个互斥目录：

```text
seed-NNN/
├── fixture.yaml
├── workspace/   # 唯一可复制给 Downstream Executor 的内容
└── oracle/      # 只供案例主持人和运行后评审使用
```

## 隔离规则

- Executor 只接收 `workspace/` 的独立副本，不得读取父目录或 `oracle/`。
- `workspace_revision.digest` 是 `sha256-tree-v1`：按相对路径排序，对每个普通文件依次哈希“路径、NUL、原始内容、NUL”。
- 任何 workspace 文件变化都会改变 digest；运行记录必须保存实际 digest。
- 不允许符号链接、密钥、真实个人数据、网络依赖或外部写入。
- `base` checks 证明起始仓库自洽，必须在实验前通过。
- `acceptance` checks 是隐藏验收；功能尚未实现时可以预期失败，不能复制给 Executor。
- 手工 oracle 必须在看到结果前冻结，不能为了让某一组通过而修改。

## 当前范围

- `seed-001`：Ruby 标准库后台用户导出基座；
- `seed-006`：无需安装依赖的 React/TypeScript 只读选型快照；
- `seed-009`：Ruby 标准库、合成知识文档的客服基座。

这些 Fixture 用于校准实验协议，不代表 PMind 产品运行时选择 Ruby 或 React。

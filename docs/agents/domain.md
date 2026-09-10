# 领域文档（Domain Docs）

说明各工程类 skill 在探索代码库时应如何消费本仓库的领域文档。

## 探索之前，先读这些

- 仓库根目录的 **`CONTEXT.md`**，或
- 若仓库根目录存在 **`CONTEXT-MAP.md`**：它指向每个上下文各自的 `CONTEXT.md`。读取与当前主题相关的每一个。
- **`docs/adr/`**：读取与你要动手的区域相关的 ADR。在多上下文仓库中，还要查看 `src/<context>/docs/adr/` 中的上下文级决策。

如果这些文件不存在，**静默跳过**。不要指出它们缺失，也不要主动建议创建。`/domain-modeling` skill（经由 `/grill-with-docs` 与 `/improve-codebase-architecture` 触达）会在术语或决策真正被确定时按需创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md`）：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← 上下文级决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表的词汇

当你的输出要命名某个领域概念时（无论出现在 issue 标题、重构提案、假设，还是测试名中），一律使用 `CONTEXT.md` 中定义的说法。不要漂移到术语表明确回避的同义词。

如果你需要的概念还不在术语表中，这是一个信号：要么你在发明项目并不使用的语言（请重新考虑），要么确实存在缺口（记录下来，交给 `/domain-modeling`）。

## 标记 ADR 冲突

如果你的输出与既有 ADR 相矛盾，请显式指出，而不是默默推翻：

> _与 ADR-0007（事件溯源订单）相矛盾，但值得重新讨论，因为……_

# Issue tracker：本地 Markdown

本仓库的 issue 与 spec 以 markdown 文件形式存放在 `.scratch/` 下。

## 约定

- 一个功能一个目录：`.scratch/<feature-slug>/`
- spec 文件为 `.scratch/<feature-slug>/spec.md`
- 实现类 issue 一个 ticket 一个文件，路径为 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，绝不合并成单个 tickets 文件
- 每个 issue 文件靠近顶部有一行 `Status:` 记录分诊状态（角色字符串见 `triage-labels.md`）
- 评论与对话历史追加到文件末尾的 `## Comments` 标题下

## 当某个 skill 要求「publish to the issue tracker」

在 `.scratch/<feature-slug>/` 下新建文件（必要时先创建目录）。

## 当某个 skill 要求「fetch the relevant ticket」

读取所引用路径的文件。用户通常直接给出路径或 issue 编号。

## Wayfinding 操作

供 `/wayfinder` 使用。**map** 是一个文件，**child** 是每个 ticket 一个文件。

- **Map**：`.scratch/<effort>/map.md`（包含 Notes / Decisions-so-far / Fog 正文）。
- **Child ticket**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 开始编号，正文写待解问题。`Type:` 行记录 ticket 类型（`research`/`prototype`/`grilling`/`task`）；`Status:` 行记录 `claimed`/`resolved`。
- **Blocking**：靠近顶部一行 `Blocked by: NN, NN`。当其中列出的每个文件都是 `resolved` 时，该 ticket 即解除阻塞。
- **Frontier**：扫描 `.scratch/<effort>/issues/`，找出未关闭、未被阻塞且未被认领的文件；编号最小者优先。
- **Claim**：在做任何工作之前先写入 `Status: claimed` 并保存。
- **Resolve**：在 `## Answer` 标题下追加答案，写入 `Status: resolved`，然后把上下文指针（要点 + 链接）追加到 `map.md` 的 Decisions-so-far 中。

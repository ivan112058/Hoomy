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

## 版本管理

- **`spec.md` 入库**：它是稳定的需求基线，改动手动提交（`.scratch/` 在 `.gitignore` 里，需 `git add -f`）。
- **`issues/` 不入库**：票据是消耗品，实现完即作废，跟随实现变动维护成本高。

## 当前状态

- **MVP spec**：`.scratch/mvp/spec.md`
- **票据**：`.scratch/mvp/issues/01-…` 至 `16-…`，共 16 张，`Status` 均为 `ready-for-agent`
- **依赖链**：`01 → 02 → 05 → 06 → 07 → 09 → 16`；`03` 与 `02` 并列（同被 `01` 阻塞）；`04`、`12`、`13`、`14` 均只被 `02` 阻塞；`08` 被 `06`；`10` 被 `01,09`；`11` 被 `09`；`15` 被 `07`；`16` 被 `06,09,12,13,14`

## 推进方式

按 **frontier** 取材：只取「其 `Blocked by` 列出的一切都已完成」的票据。

**每张票据开一个全新会话跑 `/implement`，票据之间 `/clear`。** 票据是自包含的，所以上一张的上下文可以随手丢掉 —— 不要在同一条长上下文里连做多张。做完把该票据文件的 `Status:` 改为完成态，并记下结论（尤其当票据内含「待定决策」或「回退触发点」时，例如 `16` 的 TV 导航结构、`06` 的格式验证结论）。

## 集成测试

`hoomy/test/live_server_test.dart` 对真实 Navidrome **只读**端点验真，默认跳过（默认套件不依赖网络）。要跑它需要显式传入服务器与凭据：

```
cd hoomy && flutter test test/live_server_test.dart \
  --dart-define=HOOMY_TEST_SERVER=http://<host>:4533 \
  --dart-define=HOOMY_TEST_USER=<user> \
  --dart-define=HOOMY_TEST_PASS=<pass>
```

**凭据不入库**，向用户索取。**只调用只读端点**：`ping`、`search3`、`getArtists`、`getArtist`、`getAlbumList2`、`getAlbum`、`getPlaylists`、`getPlaylist`、`getGenres`、`getStarred2`、`getLyricsBySongId`、`getLyrics`。**绝不调用** `star`、`unstar`、`scrobble` 等写端点。

## Wayfinding 操作

供 `/wayfinder` 使用。**map** 是一个文件，**child** 是每个 ticket 一个文件。

- **Map**：`.scratch/<effort>/map.md`（包含 Notes / Decisions-so-far / Fog 正文）。
- **Child ticket**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 开始编号，正文写待解问题。`Type:` 行记录 ticket 类型（`research`/`prototype`/`grilling`/`task`）；`Status:` 行记录 `claimed`/`resolved`。
- **Blocking**：靠近顶部一行 `Blocked by: NN, NN`。当其中列出的每个文件都是 `resolved` 时，该 ticket 即解除阻塞。
- **Frontier**：扫描 `.scratch/<effort>/issues/`，找出未关闭、未被阻塞且未被认领的文件；编号最小者优先。
- **Claim**：在做任何工作之前先写入 `Status: claimed` 并保存。
- **Resolve**：在 `## Answer` 标题下追加答案，写入 `Status: resolved`，然后把上下文指针（要点 + 链接）追加到 `map.md` 的 Decisions-so-far 中。

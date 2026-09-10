# Navidrome 歌词能力调研（面向 Hoomy 的 Subsonic 客户端）

- 调研日期：2026-09-09
- 代码基准：`navidrome/navidrome` `master` @ `72975a95`（2026-09-09），并回溯各 release tag 的历史实现
- 一手来源：Navidrome 仓库源码/Release/Tag/Issue/PR、`navidrome/website` 文档仓库、OpenSubsonic 规范仓库
- 说明：本文件只记录已在源码或官方发布物中核实过的事实；未能核实的条目在文末单列

## 结论速查

| 能力 | 起始版本 | 说明 |
| --- | --- | --- |
| 传统 `getLyrics`（artist+title） | v0.47.0（2021-11-18） | 仅纯文本，**主动剥离时间戳** |
| 内嵌歌词（扫描入库） | v0.47.0 | v0.51.0 起支持 USLT/SYLT 的语种与时间戳 |
| `getLyricsBySongId` + `songLyrics` 扩展 v1 广告 | **v0.51.0（2024-01-21）** | PR #2656，广告 `songLyrics: [1]` |
| 外部 `.lrc` / `.txt` sidecar | **v0.56.0（2025-05-28）** | 默认 `LyricsPriority = .lrc,.txt,embedded` |
| 外部 `.ttml` / `.elrc` / `.srt` / `.yaml`(.yml) | **v0.63.0（2026-07-08）** | PR #5076，默认优先级含全部格式 |
| `songLyrics` 扩展 **v2**（`enhanced=true`、`kind`、`cueLine`、`cue`、`byteStart/byteEnd`、`agents/agentId`） | **v0.63.0** | 广告 `songLyrics: [1, 2]` |

---

## 1. `getLyricsBySongId` 与 `songLyrics` 扩展广告的引入版本

**结论：两者都在 Navidrome v0.51.0（2024-01-21 发布）引入，由 PR #2656 "Add OS Lyrics extension" 完成（合并提交 `814161d7`）。该版本只广告 `songLyrics` 的版本 1。**

核实方式与证据：

- Release notes v0.51.0 明确写道：`[Subsonic] Add multiple OpenSubsonic extensions (See #2695)`，Changelog 中列出 `* 814161d7 Add OS Lyrics extension (#2656)`；同一 Release 的醒目提示："**NOTE:** Even though this release does not force a full rescan, you should do it at your discretion, to import more tags available in the scanner, ex: structured lyrics."（说明结构化歌词依赖重新扫描）
  - <https://github.com/navidrome/navidrome/releases/tag/v0.51.0>
- PR #2656 合并时间 2023-12-28，合并提交 `814161d7`，改动包含 `server/subsonic/api.go`（注册 `getLyricsBySongId`）、`server/subsonic/helpers.go`、`server/subsonic/media_retrieval.go`、`server/subsonic/opensubsonic.go`、`model/lyrics.go`、`scanner/metadata/taglib/taglib_wrapper.cpp` 等
  - <https://github.com/navidrome/navidrome/pull/2656>
- v0.51.0 的 `server/subsonic/opensubsonic.go` 内容为：
  ```go
  {Name: "transcodeOffset", Versions: []int32{1}},
  {Name: "formPost", Versions: []int32{1}},
  {Name: "songLyrics", Versions: []int32{1}},
  ```
  - <https://github.com/navidrome/navidrome/blob/v0.51.0/server/subsonic/opensubsonic.go>
- 版本边界核验：`grep getLyricsBySongId server/subsonic/api.go` 在 v0.49.0 / v0.49.3 / v0.50.0 / v0.50.2 命中数为 0，在 v0.51.0 为 1；`git tag --contains 814161d7` 的首个 tag 即 v0.51.0。

**置信度：高。**

> ⚠️ 顺带更正：本仓库 `docs/adr/0001-subsonic-api-and-server-side-parsing.md` 第 18 行写有"需服务端版本 ≥ 0.49 的 `getLyricsBySongId`"，与事实不符，应为 **≥ 0.51.0**。

---

## 2. 内嵌歌词解析（USLT / SYLT / Vorbis LYRICS / MP4 ©lyr）

**结论：全部支持。** 内嵌歌词在**扫描阶段**解析成结构化 JSON 存入 `media_file.lyrics` 列（不是请求时实时解析），因此升级后需要重新扫描才能拿到新格式/新字段。

### 2.1 ID3 `USLT` 与 `SYLT`（MP3，以及带 ID3v2 的 WAV/AIFF）

- v0.51.0 的 C++ TagLib 包装层显式遍历 ID3v2 frame map，分别处理 `USLT` 与 `SYLT`：
  - `USLT`：取 frame 的 3 字节 language（不足 3 字节时填 `{'x','x','x','\0'}`），把文本通过 `go_map_put_lyrics(id, language, val)` 写入映射；
  - `SYLT`：按 `AbsoluteMilliseconds`（或 `AbsoluteMpegFrames` 换算）逐行输出，通过 `go_map_put_lyric_line(...)` 组装成 `[mm:ss.xx]文本\n` 的 LRC 形式，再与 USLT 合并到同一 `lyrics-<lang>` 键。
  - <https://github.com/navidrome/navidrome/blob/v0.51.0/scanner/metadata/taglib/taglib_wrapper.cpp>
  - Go 侧把 `lyrics-<lang>` 归一为 `lyrics:<lang>`，见 <https://github.com/navidrome/navidrome/blob/v0.51.0/scanner/metadata/metadata.go> 的 `Tags.Lyrics()`
- 当前 master 换成纯 Go 的 `adapters/gotaglib`，同样显式处理原始 ID3v2 frame：`parseID3v2Frames()` 识别 `uslt:<lang>` / `sylt:<lang>` 键并写入 `lyrics:<lang>`；`parseLyrics()` 把无语言的裸 `lyrics` 归为 `lyrics:xxx`。
  - <https://github.com/navidrome/navidrome/blob/master/adapters/gotaglib/gotaglib.go>
- 端到端测试直接断言 `tests/fixtures/test.mp3` 同时包含 USLT 与 SYLT，且返回 4 条歌词（`eng`/`xxx` × USLT/SYLT），带 `Start` 时间戳：
  - <https://github.com/navidrome/navidrome/blob/master/adapters/gotaglib/end_to_end_test.go>

### 2.2 Vorbis comment `LYRICS` / `UNSYNCEDLYRICS`（FLAC / OGG / WV 等）

- 标签映射表 `resources/mappings.yaml` 中 `lyrics` 的别名同时包含 `lyrics` 与 `unsyncedlyrics`（以及 `uslt:description`）：
  ```yaml
  lyrics:
    aliases: [ uslt:description, lyrics, unsyncedlyrics ]
    type: pair # ex: lyrics:eng, lyrics:xxx
  ```
  - <https://github.com/navidrome/navidrome/blob/master/resources/mappings.yaml>
- `unsyncedlyrics` 别名是 PR #3997（`e4d65a78`，2025-04-24 合并）加入的，随 v0.56.0 发布；`git tag --contains e4d65a78` 首个 tag 为 v0.56.0。
  - <https://github.com/navidrome/navidrome/pull/3997>
  - 在此之前（v0.55.0 的 mappings.yaml）别名为 `[ uslt:description, lyrics, ©lyr, wm/lyrics ]`，不含 `unsyncedlyrics`。
- 端到端测试对 `test.flac` / `test.ogg` / `test.wv` 断言解析出两条歌词（语言 `xxx`）：
  - <https://github.com/navidrome/navidrome/blob/master/adapters/gotaglib/end_to_end_test.go>
- `tests/fixtures/mixed-lyrics.flac` 专门覆盖"同一文件里一条 synced + 一条 unsynced"，断言 `lyrics[0].Synced == true`、`lyrics[1].Synced == false`。

### 2.3 MP4 / M4A `©lyr` atom

- v0.55.0 的映射表把 `©lyr` 明确列为 `lyrics` 的别名：`aliases: [ uslt:description, lyrics, ©lyr, wm/lyrics ]`。
- master 的映射表把 `©lyr` / `wm/lyrics` 删掉了，并留有说明注释：
  ```yaml
  # Note, @lyr and wm/lyrics have been removed. Taglib somehow appears to always populate `lyrics:xxx`
  ```
  即改由 TagLib 的 PropertyMap 统一给出 `lyrics`，再由 `parseLyrics()` 归为 `lyrics:xxx`。删除动作为提交 `6730716d`（PR #4310），随 v0.58.0 发布。
  - <https://github.com/navidrome/navidrome/blob/master/resources/mappings.yaml>
  - <https://github.com/navidrome/navidrome/releases/tag/v0.58.0>（"**Lyrics tag parsing**: Properly handle both ID3 and aliased tags for lyrics. (#4310)"）
- master 端到端测试的 `format-specific lyrics` 表包含 `Entry("m4a", "test.m4a", false)`，断言 m4a 能解析出歌词，因此 `©lyr` 通路在 master 仍然有效。
  - <https://github.com/navidrome/navidrome/blob/master/adapters/gotaglib/end_to_end_test.go>

### 2.4 版本沿革补充

- v0.47.0（2021-11-18）：首次支持内嵌歌词（"Embedded lyrics are now supported by both the Subsonic API and in the UI"），当时代码只读通用的 `lyrics` / `lyrics-eng` 标签，**没有** USLT/SYLT frame 级别处理（`git show v0.47.0:scanner/metadata/taglib/taglib_wrapper.cpp | grep -c "USLT\|SYLT"` = 0，v0.49.0/v0.50.2 同样为 0）。
- v0.50.0（2023-11-17）：支持 `unsynced lyrics` 标签（#2391）。
- v0.51.0（2024-01-21）：加入 USLT/SYLT 的语种与时间戳支持（#2656）。
- 实现位置迁移：v0.51.x–v0.54.x 在 `scanner/metadata/taglib/`；v0.55.0（大重构 #2709）起在 `adapters/taglib/`；v0.60.0（#4902）起在 `adapters/gotaglib/`（纯 Go）。

**置信度：高。**

---

## 3. 外部 sidecar 歌词文件（.lrc / .txt / .elrc / .ttml / .srt / .yaml）

**结论：支持，且分两个阶段引入。**

- **v0.56.0（2025-05-28）**：引入文件系统歌词，支持 **`.lrc` 与 `.txt`**。
  - Release notes v0.56.0："**Filesystem Lyrics Support (only for Subsonic clients)**: Support for reading lyrics (.lrc) directly from filesystem files - @kgarner7 ([#2897](...), [#3997](...))"
    <https://github.com/navidrome/navidrome/releases/tag/v0.56.0>
  - 该版本 `conf/configuration.go` 的默认值为 `viper.SetDefault("lyricspriority", ".lrc,.txt,embedded")`（v0.56.0 之前没有 `lyricspriority` 默认值项）。
  - PR #2897 合并于 2025-04-30：<https://github.com/navidrome/navidrome/pull/2897>
- **v0.63.0（2026-07-08）**：扩展为 **`.ttml` / `.yaml` / `.yml` / `.elrc` / `.lrc` / `.srt` / `.txt`**。
  - Release notes v0.63.0 中 `LyricsPriority` 变更行为 `.ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded`；正文："Add structured sidecar lyrics support with OpenSubsonic v2 karaoke cues and agent layers: TTML, ELRC, SRT and YAML sidecar files are now parsed with word-by-word timing and multi-voice information. (#5076)"
    <https://github.com/navidrome/navidrome/releases/tag/v0.63.0>
  - master `conf/configuration.go`：`viper.SetDefault("lyricspriority", ".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded")`
    <https://github.com/navidrome/navidrome/blob/master/conf/configuration.go>
  - master `README.md`："Supports **lyrics** from sidecar .ttml, .yaml/.yml Lyricsfile, .elrc, .lrc, .srt, .txt files and embedded TTML, Enhanced LRC, LRC, SRT, and plain-text tags (via `lyricspriority`)"
- 其它相关修复：
  - v0.57.0：修复"内嵌歌词为空时（`media_file.lyrics` 为 `[]`）不去读外部文件"（#4232/#4233）与多实例检测（#4237）。
    <https://github.com/navidrome/navidrome/releases/tag/v0.57.0>
  - 早先的社区 PR #3632（.lrc 支持）**未合并**（2025-05-25 closed，被 #2897 取代）。
    <https://github.com/navidrome/navidrome/pull/3632>
- 解析机制：`core/lyrics/lyrics.go` 按 `LyricsPriority` 逐项尝试（`embedded` 内嵌 / 以 `.` 开头的走 sidecar / 其余当作插件名）；sidecar 读取 `core/lyrics/sources.go`，用同目录同名文件（换扩展名）`model.ParseLyrics(ctx, suffix, "xxx", contents)` 解析。`.elrc` 走 LRC/Enhanced-LRC 解析器（`lyricFormats` 只登记 `.ttml`/`.srt`/`.yaml|.yml`，其余后缀回落到 LRC/纯文本地板）。
  - <https://github.com/navidrome/navidrome/blob/master/core/lyrics/lyrics.go>
  - <https://github.com/navidrome/navidrome/blob/master/core/lyrics/sources.go>
  - <https://github.com/navidrome/navidrome/blob/master/model/lyrics_parse.go>
- 重要语义：sidecar 是**请求时按需读取**（不在扫描时入库），所以新增/修改 sidecar 不需要重新扫描；内嵌歌词则相反，扫描时入库。

**置信度：高。**

---

## 4. 内嵌歌词的返回形态（`synced`、`line.start`、`lang`）

**结论：符合预期，且语言未知时返回 `xxx`（不是 `und`）。**

- **未同步（USLT / Vorbis LYRICS 纯文本）**：`synced: false`，`line` 内只有 `value`、没有 `start`。
- **已同步（SYLT / Enhanced LRC / TTML / SRT / YAML）**：`synced: true`，`line` 项带 `start`（毫秒）。
- 判定逻辑（当前 master `model/lyrics_lrc.go`，与 v0.51.0 `model/lyrics.go` 一致）：`synced := syncRegex.MatchString(text)`，其中 `syncRegex = (^|\n)\s*\[([0-9]{1,2}:)?([0-9]{1,2}):([0-9]{1,2})(\.[0-9]{1,3})?\]` —— 即"文本中存在位于行首（或文件开头）的 `[mm:ss]` 时间标记"就判定为同步；TTML/SRT/YAML 解析器则各自显式设置 `Synced`（TTML 用 `linesAreSynced()`）。
  - <https://github.com/navidrome/navidrome/blob/master/model/lyrics_lrc.go>
  - <https://github.com/navidrome/navidrome/blob/master/model/lyrics_ttml.go>
- SYLT → 时间戳的转换在 v0.51.0 的 `taglib_wrapper.go` 中完成：`[mm:ss.xx]文本\n`，`ms/10` 作为两位小数；随后由 LRC 解析器产出 `Start`。
  - <https://github.com/navidrome/navidrome/blob/v0.51.0/scanner/metadata/taglib/taglib_wrapper.go>
- **`lang` 字段：Navidrome 返回 `xxx`，代码中不存在 `und` 分支。**
  - 内嵌无语言：`adapters/gotaglib/gotaglib.go` 的 `parseLyrics()` 把裸 `lyrics` 移到 `lyrics:xxx`；v0.51.0 的 C++ 层在 language 非 3 字节时填 `{'x','x','x'}`。
  - 外部 sidecar：`core/lyrics/sources.go` 固定传 `"xxx"` 作为默认语言；TTML 的 `normalizeLyricLang()` 空值同样返回 `"xxx"`；LRC 的 `[lang:xx]` 可覆盖。
  - 端到端测试用例显式断言：`embedded plain text → (synced=false, lang="xxx")`、`embedded enhanced LRC → (true, "eng")`、`SRT sidecar → (true, "xxx")`、`YAML sidecar → (true, "eng")`。
    <https://github.com/navidrome/navidrome/blob/master/server/subsonic/e2e/subsonic_lyrics_test.go>
- OpenSubsonic 规范允许二者之一：`lang` 字段说明为 "If the language is unknown (e.g. lrc file), the server **must** return `und` (ISO standard) or `xxx` (common value for taggers)"。
  - <https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/structuredLyrics.md>

**置信度：高。**

---

## 5. `songLyrics` v2（卡拉OK级字段）与版本

**结论：Navidrome 从 v0.63.0（2026-07-08）起广告并实现 `songLyrics` v2。** v0.51.0–v0.62.x 只广告/实现 **v1**。

- 当前 master 广告（v0.63.0 起一致）：
  ```go
  {Name: "songLyrics", Versions: []int32{1, 2}},
  ```
  - v0.51.0 为 `Versions: []int32{1}`（见第 1 条）。
  - master：<https://github.com/navidrome/navidrome/blob/master/server/subsonic/opensubsonic.go>
  - v0.63.0：<https://github.com/navidrome/navidrome/blob/v0.63.0/server/subsonic/opensubsonic.go>
- `enhanced=true` 参数在 `GetLyricsBySongId` 中读取：`enhanced, _ := req.Params(r).Bool("enhanced")`；`buildLyricsList()` 在非 enhanced 时**只保留 main kind 且不输出任何 v2 字段**。
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/media_retrieval.go>
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/lyrics.go>
- 字段落点（响应结构体，`server/subsonic/responses/responses.go`）：
  - `StructuredLyric`：`kind`、`agents`、`cueLine`（以及既有 `lang`/`line`/`offset`/`synced`/`displayArtist`/`displayTitle`）
  - `CueLine`：`index`、`start`、`end`、`value`、`agentId`、`cue[]`
  - `LyricCue`：`start`、`end`、`byteStart`、`byteEnd`、`value`
  - `Agent`：`id`、`role`、`name`
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/responses/responses.go>
- 端到端测试断言 v2 行为：`?enhanced=true` 时每条 `kind == "main"`，仅携带词级时间的来源（内嵌 Enhanced LRC / 内嵌 TTML / YAML sidecar）才产出 `cueLine`（示例断言首个 cueLine 含 5 个 cue、`cue[0].Value == "Should "`）；LRC/SRT/纯文本无 cueLine；**不加 `enhanced` 时 `cueLine`/`kind`/`agents` 必须全为空**。
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/e2e/subsonic_lyrics_test.go>
- 版本引入来源：PR #5076（`feat(subsonic): add structured sidecar lyrics support with OpenSubsonic v2 karaoke cues and agent layers`，2026-06-19 合并，合并提交 `3a14faa0`），首个包含它的 tag 是 v0.63.0；PR #5632（`refactor(lyrics): single ParseLyrics entry point + all-format plugin lyrics`，同一版本）负责统一解析入口与插件多格式。
  - <https://github.com/navidrome/navidrome/pull/5076>
  - <https://github.com/navidrome/navidrome/pull/5632>
- 上游规范：v2 明确定义 `enhanced` 参数、`kind`、`agents`、`cueLine`、`cue`（含必填 `byteStart`/`byteEnd`，为 `cueLine.value` 的 0 基闭区间 UTF-8 字节偏移），并要求支持 v2 的服务器广告 `songLyrics: [1, 2]`。
  - <https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Extensions/songLyrics.md>
  - <https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/cueLine.md>
  - <https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/cue.md>
- 跟踪 issue #2695 中两项均已勾选：`- [x] [songLyrics](...): #2656` 与 `- [x] [songLyrics v2](...)`。
  - <https://github.com/navidrome/navidrome/issues/2695>

**置信度：高。**

---

## 6. 已知 bug / 怪癖

### 6.1 issue #4631「只有一行歌词时 `synced` 恒为 false」

- **已修复，随 v0.58.5（2025-11-09）发布。**
- 真实根因**不是**"单行"逻辑，而是 .lrc 文件开头的 **UTF-8 BOM**：`syncRegex` 要求时间标记出现在文件开头或行首，BOM 落在 `[00:00.00]` 之前导致首行不被识别；当文件里还有第二行时，第二行前面有 `\n`，于是又能匹配 —— 这解释了"加一行就好了"的现象。维护者 `kgarner7` 用 `cat -A` 展示了 `M-oM-;M-?`（即 EF BB BF）。
- 时间线：issue 2025-10-29 建，2025-10-31 由 PR #4637 修复并关闭（state_reason: completed）。
- 修复提交 `91fab685`（PR #4637 "fix: handle UTF BOM in lyrics and playlist files"），`git tag --contains 91fab685` 首个 tag 为 v0.58.5；v0.58.5 release notes ："Handle UTF BOM in lyrics and playlist files. (#4637)"
  - <https://github.com/navidrome/navidrome/issues/4631>
  - <https://github.com/navidrome/navidrome/pull/4637>
  - <https://github.com/navidrome/navidrome/releases/tag/v0.58.5>
- 当前 master 的修复点在 `model/lyrics_parse.go` 的 `stripBOM()`（以及各解析入口）。
  - <https://github.com/navidrome/navidrome/blob/master/model/lyrics_parse.go>

### 6.2 discussion #2982「Timestamp Missing for Lyrics Obtained via Subsonic API」

- **不是 bug，是刻意设计，没有"修复版本"。**
- 维护者 `deluan` 的回答：剥离时间戳是因为"most (all?) Subsonic clients do not expect timestamps when calling the getLyrics endpoint"，并为此在 OpenSubsonic 中讨论并实现了新的 `getLyricsBySongId`。
- 代码印证：传统 `GetLyrics` 把 `mainLyric.Line` 的 `Value` 用 `\n` 拼接后返回，`start` 被丢弃；该行为自 PR #1379（commit `5621551d`，随 v0.47.0 发布，提交信息含 "remove timestamps frorom the the lyrics if they are synced"）起就存在。
  - <https://github.com/navidrome/navidrome/discussions/2982>
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/media_retrieval.go>
  - <https://github.com/navidrome/navidrome/releases/tag/v0.47.0>

### 6.3 对客户端的实际影响

1. **要时间轴就必须用 `getLyricsBySongId`**，绝不能指望 `getLyrics`；后者的 `value` 里连 LRC 方括号、SRT `-->`、TTML 标签都被剥掉了（端到端测试对这一点有硬断言）。
2. **先探测 `getOpenSubsonicExtensions`**：`songLyrics` 存在且 `versions` 含 `2` 才请求 `enhanced=true`；不含 2 时即使发了参数也拿不到 v2 字段（v1 实现根本不认识该参数）。
3. **服务端版本下限**：想要时间轴 ≥ v0.51.0；想要外部 sidecar（`.lrc`/`.txt`）≥ v0.56.0；想要 `.ttml`/`.elrc`/`.srt`/`.yaml` 与词级卡拉OK ≥ v0.63.0。
4. **判断 synced 的正确姿势**：以服务端 `synced` 字段为准，但要注意其判定基于"行首时间标记"的正则；对 v0.58.5 以前的服务端，带 BOM 的单行 LRC 会误报 `synced:false`，客户端可做兜底（例如自行用 `[mm:ss]` 正则探测 `line.value`）。
5. **`line[].value` 在 v1 下可能仍含 LRC 时间标记**：v0.58.5 之前的 BOM 场景里，`value` 原样带 `[00:00.00]`；而正常路径下时间戳被解析到 `start` 且从 `value` 剥离。客户端不要假设 `value` 一定干净。

---

## 7. 传统 `getLyrics`（artist+title）返回什么

**结论：只返回纯文本，不返回时间戳。**

- Navidrome 官方兼容性文档："`getLyrics` — Works with embedded lyrics and external files"。
  - <https://github.com/navidrome/website/blob/master/content/en/docs/developers/subsonic-api.md>
  - 渲染版：<https://www.navidrome.org/docs/developers/subsonic-api/>
- 但"支持内嵌与外部文件"指的是**取词来源**，不代表保留时间轴。master 实现：
  ```go
  mainLyric, ok := structuredLyrics.Main()
  ...
  for _, line := range mainLyric.Line {
      lyricsText.WriteString(line.Value + "\n")
  }
  lyricsResponse.Value = lyricsText.String()
  ```
  `Line.Start` 完全未参与输出；`Main()` 只取 `kind == "main"`（空 kind 视为 main）的第一条，翻译/发音层被丢弃。
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/media_retrieval.go>
  - <https://github.com/navidrome/navidrome/blob/master/model/lyrics.go>（`LyricList.Main()`）
- v0.51.0 的实现同样是 `lyricsText += line.Value + "\n"`：
  - <https://github.com/navidrome/navidrome/blob/v0.51.0/server/subsonic/media_retrieval.go>
- 端到端测试对 ELRC/TTML/SRT/YAML 各种来源都断言 `getLyrics` 的 `value` **不含** `[`、`-->`、`<`：
  - <https://github.com/navidrome/navidrome/blob/master/server/subsonic/e2e/subsonic_lyrics_test.go>

**置信度：高。**

---

## 版本时间线（发布日，便于做兼容矩阵）

| 版本 | 发布日 | 歌词相关变化 |
| --- | --- | --- |
| v0.47.0 | 2021-11-18 | 内嵌歌词 + 传统 `getLyrics`（#1379）；`getLyrics` 起就剥离时间戳 |
| v0.50.0 | 2023-11-17 | 支持 `unsynced lyrics` 标签（#2391） |
| v0.51.0 | 2024-01-21 | `getLyricsBySongId` + `songLyrics` v1（#2656）；USLT/SYLT 语种与时间戳 |
| v0.53.0 | 2024-09-17 | 修复 OpenSubsonic 结构化歌词的 XML 序列化（#3041） |
| v0.55.0 | 2025-03-09 | 新扫描器大重构（#2709），`mappings.yaml` 引入，含 `©lyr` |
| v0.56.0 | 2025-05-28 | 外部 `.lrc`/`.txt`（#2897、#3997）；新增 `unsyncedlyrics` 别名 |
| v0.57.0 | 2025-07-01 | 内嵌为空时回退外部文件（#4232）；多实例检测（#4237） |
| v0.58.0 | 2025-07-28 | ID3/别名歌词标签解析重构（#4310） |
| v0.58.5 | 2025-11-09 | 修复 UTF-8 BOM 导致 `synced` 误判（#4637） |
| v0.60.2 | 2026-02-07 | 保留歌词首行括号（#4985） |
| v0.61.0 | 2026-03-31 | 歌词 provider 插件能力（#5126） |
| v0.63.0 | 2026-07-08 | `.ttml`/`.elrc`/`.srt`/`.yaml` sidecar + `songLyrics` **v2**（#5076、#5632） |
| v0.63.2 | 2026-07-11 | 截至调研时最新 release |

---

## 未能核实 / 存疑项

1. **`#2982` 中引用的 "PR #249"**：讨论原文写"done intentionally in this PR: #249"，但 `navidrome/navidrome#249` 实为 2021 年的 **issue**「Support for Lyrics - Subsonic API」，并非剥离时间戳的 PR。实际剥离行为的可考证来源是 PR #1379（commit `5621551d`，v0.47.0）。我检查了 v0.47.0 的 `GetLyrics` 实现与提交信息，未能确认讨论中 #249 这个编号的确切指向，故不采信该编号。
2. **`#2982` 的精确状态（是否 answered/locked）**：GitHub Discussions 无 REST API，我用 HTML 页面提取了正文与维护者回复，页面存在 "answered" 标记，但未能通过结构化 API 核实其分类与置顶答案是否被正式接受。
3. **各发行版 Docker 镜像/二进制是否与 tag 源码完全一致**：未核实（本次只读源码 tag 与 release notes）。
4. **v0.51.0 之前（v0.47.0–v0.50.2）MP4 `©lyr` / Vorbis `LYRICS` 是否真的被 TagLib PropertyMap 归一为 `lyrics`**：v0.47.0–v0.50.x 的代码只按 `lyrics`/`lyrics-eng` 取值（`Tags.Lyrics()`），我**没有**用真实 fixture 在那些版本上跑过，因此"v0.47.0 起就支持 `©lyr`/Vorbis LYRICS"属于**推断**；可确证的是 v0.51.0 的 format-specific 测试（flac/m4a/ogg 等，`id3Lyrics=false`）已明确断言这些格式解析出 `lyrics`，master 亦有等价测试。
5. **Navidrome 是否在任何路径返回 `und`**：我在 `model/`、`core/lyrics/`、`adapters/`、`scanner/` 全量 grep 未发现 `"und"` 字面量，只有 `"xxx"`；因此判断"只返回 `xxx`"。这是基于源码检索的结论，非官方声明。

# Subsonic API 与 Navidrome 能力核实报告

调研日期：2026-09-10
调研对象：Hoomy Flutter 客户端通过 Subsonic 兼容 API 对接 Navidrome（局域网 NAS 音乐播放）。

## 方法与来源

只采用一手来源：

- Subsonic 官方 API 文档 <https://www.subsonic.org/pages/api.jsp> 与官方 XSD
  <https://www.subsonic.org/pages/inc/api/schema/subsonic-rest-api-1.16.1.xsd>
- OpenSubsonic 规范 <https://opensubsonic.netlify.app/> 与仓库
  <https://github.com/opensubsonic/open-subsonic-api>
- Navidrome 官方文档 <https://www.navidrome.org/>、官网仓库 `navidrome/website`、
  服务端仓库 `navidrome/navidrome`（源码 / Release Notes / PR / Issue）

未使用博客或问答站内容。凡无法用一手来源确认的，均在正文标注「未能核实」，
并在文末「未能核实清单」集中列出。

置信度标记：**高**（官方文档或源码可直接印证）、**中**（由源码推导但无文档/测试背书）、
**低**（仅间接迹象）。

## 结论速览

| 事项 | 结论 |
| --- | --- |
| `getLyrics` | 核心 Subsonic 端点（1.2.0），按 `artist`+`title` 查，返回**纯文本** `lyrics`，**不支持时间戳** |
| `getLyricsBySongId` | OpenSubsonic 扩展 `songLyrics`，按歌曲 ID 返回结构化歌词，**支持逐行同步 LRC** |
| 逐字（karaoke） | OpenSubsonic `songLyrics` **版本 2** 新增，需 `enhanced=true`，字段为 `cueLine`/`cue` |
| Navidrome 歌词内嵌解析 | 支持 ID3 `USLT`/`SYLT`、`LYRICS`/`UNSYNCEDLYRICS`；M4A `©lyr` 经 TagLib 属性映射 |
| 全库歌曲列表 | `search3` + **空 `query`** + `songCount`/`songOffset`；OpenSubsonic 明确要求空 query 返回全量 |
| 收藏 | `star`/`unstar`/`getStarred2` 均为**核心 Subsonic**（1.8.0），非扩展；歌曲/专辑/歌手三粒度都支持 |
| 认证 | `t = md5(password + salt)`，`s` 为每次随机 salt；1.13.0 起官方推荐；自签证书无标准客户端信任机制 |
| 原始流 | `stream?format=raw`（1.9.0 起）；`download` 亦返回原始数据 |
| API 版本 `v` | 填 `1.16.1`；OpenSubsonic 扩展通过响应 `openSubsonic` 标志 + `getOpenSubsonicExtensions` 探测 |

---

## 1. 歌词

### 1.1 `getLyrics`（核心 Subsonic，无时间戳）

- 端点：`/rest/getLyrics.view`，自 **1.2.0** 起。
  参数：`artist`（可选）、`title`（可选）。
- 返回：`<subsonic-response>` 内嵌 `<lyrics>` 元素，**无歌词时该元素为空**（不是错误）。
- 官方 XSD 中 `Lyrics` 类型的定义只有 `artist`、`title` 两个属性和 mixed 文本内容，
  **没有任何时间戳字段** —— 因此 `getLyrics` 不支持同步（LRC）歌词：

  ```xml
  <xs:complexType name="Lyrics" mixed="true">
      <xs:attribute name="artist" type="xs:string" use="optional"/>
      <xs:attribute name="title"  type="xs:string" use="optional"/>
  </xs:complexType>
  ```
- OpenSubsonic 未对该端点做任何增强（OS 页面参数表与核心文档一致，只有 `artist`/`title`）。

来源：<https://www.subsonic.org/pages/api.jsp>（`getLyrics` 节）；
<https://www.subsonic.org/pages/inc/api/schema/subsonic-rest-api-1.16.1.xsd>（`Lyrics` 类型）；
<https://opensubsonic.netlify.app/docs/endpoints/getlyrics/>
置信度：**高**。

### 1.2 `getLyricsBySongId`（OpenSubsonic 扩展 `songLyrics`）

- 它是 OpenSubsonic **扩展**，扩展名为 `songLyrics`，OpenSubsonic 版本 1。
  扩展通过 `getOpenSubsonicExtensions` 声明。
- 端点：`/rest/getLyricsBySongId.view`。参数：`id`（必填，歌曲 ID）；
  `enhanced`（可选，默认 `false`，**版本 2 新增**）。
- 返回：`subsonic-response` → `lyricsList` → `structuredLyrics` 数组。
  `lyricsList` 是 OpenSubsonic 新增响应类型，`structuredLyrics` 元素数量可为 0（无歌词）。
- `structuredLyrics` 字段（版本 1）：

  | 字段 | 类型 | 必填 | 说明 |
  | --- | --- | --- | --- |
  | `lang` | string | 是 | 语言（理想为 ISO 639）。未知时服务端应返回 `und` 或 `xxx` |
  | `synced` | boolean | 是 | 是否为同步歌词 |
  | `line` | line 数组 | 是 | 歌词正文；同步按时间排序，非同步按出现顺序 |
  | `displayArtist` | string | 否 | 展示用艺术家名 |
  | `displayTitle` | string | 否 | 展示用标题 |
  | `offset` | number | 否 | 全局偏移（毫秒）。**正数表示歌词更早出现**；缺省按 0 处理 |

- `line` 字段（版本 1）：

  | 字段 | 类型 | 必填 | 说明 |
  | --- | --- | --- | --- |
  | `value` | string | 是 | 该行文本 |
  | `start` | number | 否 | 相对音轨开始的毫秒数；**非同步歌词必须省略** |

  注意：`line` **没有 `end` 字段**。`end` 只出现在版本 2 的 `cueLine`/`cue` 上。

来源：<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Extensions/songLyrics.md>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Endpoints/getLyricsBySongId.md>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/structuredLyrics.md>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/line.md>
置信度：**高**。

### 1.3 逐字（增强 LRC / word-level karaoke）—— `songLyrics` 版本 2

OpenSubsonic `songLyrics` **版本 2** 增加逐字/逐音节能力，需要请求带 `enhanced=true`：

- 新增 `kind` 字段：`main`（默认，主唱层）、`translation`（翻译层）、`pronunciation`（音译层）。
  各层相互独立，**不保证行/字一一对应**。
- 新增 `cueLine` 数组（与 `line` **平行**，不是替代）：每个 `cueLine` 通过 `index` 对应 `line`。
  字段：`index`、`start`、`end`、`value`、`agentId`（可选）、`cue` 数组。
- 新增 `cue` 数组：逐字/逐音节时间片。字段：`start`、`end`（可选）、`value`、
  **`byteStart` / `byteEnd`**（0 基、**闭区间**，指向该 `cueLine.value` 的 UTF-8 字节偏移）。
- 新增 `agents` 数组与 `cueLine.agentId`：多声部/多演唱者归属。
  `agents[].role` 取值含 `main`、`voice`、`bg`、`group`；`agents[].id` 仅在该 `structuredLyrics` 内有效。

约束要点（对客户端渲染有影响）：

- 只有 `synced=true` 才可能有 `cueLine`；服务端**不得**为未同步歌词输出 `cueLine`。
- 所有 `cue` 的 `end` 要么全有要么全无；服务端需规范化重叠。
- `cueLine.value` 是该层可独立渲染的文本；跨 agent 时不要用 `line[index].value` 当单层文本。
- **不带 `enhanced=true` 时，响应与版本 1 完全一致**（不返回 `kind` 与 `cueLine`），
  即向后兼容。
- 支持版本 2 的服务端应通过 `getOpenSubsonicExtensions` 声明 `songLyrics` 的 `versions` 为 `[1, 2]`。

来源：<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Extensions/songLyrics.md>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Endpoints/getLyricsBySongId.md>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Responses/structuredLyrics.md>
置信度：**高**。

### 1.4 Navidrome 支持情况与版本

来自 Navidrome Release Notes（GitHub Releases，官方一手）：

| Navidrome 版本 | 日期 | 歌词相关变化 |
| --- | --- | --- |
| v0.47.0 | 2021-11-18 | 内嵌歌词同时支持 Subsonic API 与 UI；新增 `GetLyrics` 端点（#1379） |
| v0.50.0 | 2023-11-17 | 扫描器支持 `unsynced lyrics` 标签（#2391） |
| **v0.51.0** | **2024-01-21** | **`Add OS Lyrics extension (#2656)` —— 引入 OpenSubsonic 结构化歌词（即 `getLyricsBySongId`）** |
| v0.52.5 | 2024-05-12 | 对乱序重复歌词排序（#2989） |
| v0.53.0 | 2024-09-17 | 修复 OpenSubsonic 结构化歌词响应（#3041） |
| v0.56.0 | 2025-05-28 | 支持从文件系统读取 `.lrc` 侧车文件（#2897、#3997） |
| v0.57.0 | 2025-07-01 | 修复内嵌歌词为空时不回退外部文件的问题（#4232） |
| v0.58.0 | 2025-07-28 | 歌词标签解析兼容 ID3 及别名标签（#4310） |
| v0.63.0 | 2026-07-08 | **OpenSubsonic v2 逐字歌词**与多声部（agent）层；侧车 TTML/ELRC/SRT/YAML/LRC；`LyricsPriority` 默认值改为 `.ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded` |

关键结论：

- **`getLyricsBySongId` 自 Navidrome v0.51.0 起可用**（不是 0.49）。
  → `docs/adr/0001-subsonic-api-and-server-side-parsing.md` 中「需服务端版本 ≥ 0.49 的
  `getLyricsBySongId`」这一表述**不准确**，应修正为 **≥ 0.51.0**。
- **逐字 karaoke（`songLyrics` v2）自 v0.63.0 起可用**。
- 扩展广告的版本边界（经逐 tag 回溯源码确认）：
  - **v0.51.0 起**：`{Name: "songLyrics", Versions: []int32{1}}`，只有版本 1。
  - **v0.63.0 起**：`{Name: "songLyrics", Versions: []int32{1, 2}}`，同时支持版本 2。
  - v0.49.x / v0.50.x 的 `api.go` 中不存在 `getLyricsBySongId` 路由。
- 歌词在**扫描阶段**解析并写入数据库（`media_file.lyrics`）。因此**升级 Navidrome 后需要重新扫描**
  曲库，旧数据才会带上结构化歌词（v0.51.0 与 v0.63.0 的 Release Notes 都提示了这一点）。
- 内嵌歌词经扫描入库后由 `core/lyrics/sources.go` 的 `fromEmbedded` 读取；
  `server/subsonic/lyrics.go` 的 `buildLyricsList` 依据 `enhanced` 决定是否过滤非 `main` 层。

来源：
<https://github.com/navidrome/navidrome/releases>（v0.47.0 / v0.50.0 / v0.51.0 / v0.56.0 / v0.58.0 / v0.63.0 Release Notes）；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/opensubsonic.go>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/lyrics.go>；
<https://github.com/navidrome/navidrome/blob/master/core/lyrics/sources.go>；
Navidrome Subsonic API 兼容文档 <https://www.navidrome.org/docs/developers/subsonic-api/>
置信度：**高**（版本号来自官方 Release Notes；扩展声明来自源码）。

### 1.5 Navidrome 的内嵌歌词解析

Navidrome 的标签读取实现是 `adapters/gotaglib/gotaglib.go`（基于 go-taglib / TagLib WASM），
标签到内部字段的映射在 `resources/mappings.yaml`。与歌词相关的部分：

- `resources/mappings.yaml` 中 `lyrics` 的别名（aliases）为：

  ```yaml
  lyrics:
    aliases: [ uslt:description, lyrics, unsyncedlyrics ]
    maxLength: 1048576
    type: pair   # 形如 lyrics:eng / lyrics:xxx
  ```

- ID3v2 帧：`gotaglib.go` 的 `parseID3v2Frames` 显式处理 **`USLT:<lang>`** 与 **`SYLT:<lang>`**，
  把带语言码的歌词归一到 `lyrics:<lang>`；若存在语言特定歌词，则删除通用 `lyrics`。
- Vorbis Comment / FLAC：由 TagLib PropertyMap 归一到 `LYRICS`，别名表覆盖 `lyrics` 与
  `unsyncedlyrics`。
- MP4/M4A `©lyr`：v0.55.0 的 `mappings.yaml` 曾把它显式列为别名
  （`[ uslt:description, lyrics, ©lyr, wm/lyrics ]`）；v0.58.0 起（PR #4310）删除了这两条显式别名，
  改由 TagLib PropertyMap 统一产出 `lyrics:xxx`，`mappings.yaml` 内有注释说明
  「`@lyr` 与 `wm/lyrics` 已被移除，TagLib 似乎总会填充 `lyrics:xxx`」。
  其裸的 `parseMP4Atoms` 处理 MP4 原子并把 iTunes 前缀（`----:com.apple.iTunes:`）剥离后小写化。
  → `©lyr` 在旧版是显式别名，在 v0.58.0+ 经 TagLib 属性映射进入 `lyrics`。
- `unsyncedlyrics` 别名由 PR #3997 于 v0.56.0 加入。
- 端到端测试覆盖：`adapters/gotaglib/end_to_end_test.go` 断言 `test.mp3` 同时含 USLT 与 SYLT
  （共 4 条，含 `eng`/`xxx`），format 表含 flac/m4a/ogg/wma/wv；
  `tests/fixtures/mixed-lyrics.flac` 另有「1 条 synced + 1 条 unsynced」的断言。
- 侧车文件：`core/lyrics/sources.go` 的 `fromExternalFile` 按 `LyricsPriority` 列表查找同名文件，
  调用 `model.ParseLyrics`。v0.63.0 起支持 TTML/ELRC/SRT/YAML/LRC。
- 语言缺省：`gotaglib.go` 的 `parseLyrics` 把无语言码的 `lyrics` 改写成 `lyrics:xxx`；
  外部文件解析也传 `"xxx"`；TTML 的 `normalizeLyricLang()` 空值同样返回 `"xxx"`。
  因此 Navidrome 对未知语言返回 **`xxx`**，
  按 OpenSubsonic 要求客户端应把 `xxx` 视为「未指定语言」（等价 `und`）。
  （代码中只出现 `"xxx"`，未出现 `"und"` —— 这是对 `model/`、`core/lyrics/`、`adapters/`、
  `scanner/` 全量检索的结论，**非官方声明**。）
- 同步判定：`model/lyrics_lrc.go` 用 `syncRegex`（匹配行首或文件开头的 `[mm:ss]`）判断 `synced`；
  TTML 走 `linesAreSynced()`。

返回形式：

- 内嵌**非同步**歌词（`USLT`、Vorbis `LYRICS`、`©lyr`）→ `synced: false`，`line[].start` 省略。
- 内嵌**同步**歌词（ID3 `SYLT`）→ `synced: true`，`line[].start` 为毫秒时间戳。

来源：
<https://github.com/navidrome/navidrome/blob/master/adapters/gotaglib/gotaglib.go>；
<https://github.com/navidrome/navidrome/blob/master/resources/mappings.yaml>；
<https://github.com/navidrome/navidrome/blob/master/model/metadata/metadata.go>；
<https://github.com/navidrome/navidrome/blob/master/core/lyrics/sources.go>；
<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Endpoints/getLyricsBySongId.md>（`lang` 说明）
置信度：ID3 `USLT`/`SYLT`、`LYRICS`/`UNSYNCEDLYRICS`、MP4 `©lyr`、`xxx` 默认值 —— **高**
（源码别名表 + 端到端测试 + 逐版本回溯）；
「Navidrome 从不返回 `und`」—— **中**（全量 grep 结论，非官方声明）。

### 1.6 服务端不支持时的处理与降级路径

- **Subsonic 错误码里没有「端点不存在／扩展不支持」这一项。** 已定义码为：
  `0` 通用错误、`10` 缺参数、`20`/`30` 协议版本不兼容、`40` 用户名密码错误、
  `41` LDAP 用户不支持 token、`42` 认证机制不支持、`43` 认证机制冲突、`44` 无效 API key、
  `50` 无权限、`60` 试用过期、`70` 请求数据未找到。
  因此**不能依赖某个错误码来判定端点是否受支持**。
- 正确做法是**能力探测**（见第 6 节）：
  1. 读任意响应的 `subsonic-response.openSubsonic` 是否为 `true`；
  2. 调 `getOpenSubsonicExtensions`，在其中查找 `name == "songLyrics"` 及其 `versions`；
  3. 再决定调用 `getLyricsBySongId`（并可据 `versions` 是否含 `2` 决定是否传 `enhanced=true`）。
- 降级路径建议：`getLyricsBySongId`（可同步、可逐字）→ 不支持时回退 `getLyrics`
  （纯文本，按 `artist`+`title` 查）→ 两者都无内容时不显示歌词入口。
- `getLyrics` **无歌词返回空 `<lyrics>` 元素而非错误**，客户端需把「空元素」当作「无歌词」而非失败。

来源：<https://www.subsonic.org/pages/api.jsp>（Error handling）；
<https://opensubsonic.netlify.app/docs/responses/error/>；
<https://opensubsonic.netlify.app/docs/endpoints/getopensubsonicextensions/>
置信度：**高**（错误码清单与空 `lyrics` 语义）。
「未实现 `getLyricsBySongId` 的服务端具体返回什么（HTTP 404 还是 error code 0）」
—— **未能核实**，规范未规定；故应走能力探测而非猜测错误码。

### 1.7 已知 bug 与怪癖（客户端需做的兜底）

- **一行歌词 `synced` 恒为 false（Navidrome issue #4631）—— 已修复。**
  真因不是「只有一行」，而是 **`.lrc` 文件开头的 UTF-8 BOM**：BOM 使首行 `[mm:ss]` 不满足
  `syncRegex`（第二行因前面有换行符所以能匹配），从而被误判为非同步。
  由 PR #4637 修复，**随 v0.58.5（2025-11-09）发布**。
  → 客户端在旧版上可自行用正则兜底，并注意 BOM 场景下 `line[].value` 会**原样带上**
  `[00:00.00]` 前缀（值不干净）。
- **`getLyrics` 不含时间戳（discussion #2982）—— 不是 bug，是刻意设计。**
  维护者 deluan 表示「大多数（全部？）Subsonic 客户端在调用 `getLyrics` 时不预期时间戳」，
  因此 Navidrome **主动剥离**时间戳，另设 `getLyricsBySongId` 提供时间轴；
  并且 Navidrome 的 `getLyrics` 只拼接 `kind == main` 的行，
  **丢弃 `translation`/`pronunciation` 层**。该行为自 v0.47.0（PR #1379）起存在，无修复版本。
  → 需要时间轴必须用 `getLyricsBySongId`。
- **版本下限小结**：时间轴 ≥ v0.51.0；`.lrc`/`.txt` 侧车 ≥ v0.56.0；
  `.ttml`/`.elrc`/`.srt`/`.yaml` 与逐字卡拉 OK ≥ v0.63.0。

来源：<https://github.com/navidrome/navidrome/issues/4631>；
<https://github.com/navidrome/navidrome/pull/4637>；
<https://github.com/navidrome/navidrome/discussions/2982>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/media_retrieval.go>
置信度：**高**（#4631 修复版本经 `git tag --contains` 回溯；#2982 为维护者明确表态）。

---

## 2. 全库歌曲列表与分页

### 2.1 `search3` 的参数与响应结构

参数（官方文档）：

| 参数 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `query` | 是 | 无 | 搜索词 |
| `artistCount` | 否 | 20 | 艺术家数上限 |
| `artistOffset` | 否 | 0 | 艺术家偏移 |
| `albumCount` | 否 | 20 | 专辑数上限 |
| `albumOffset` | 否 | 0 | 专辑偏移 |
| `songCount` | 否 | 20 | 歌曲数上限 |
| `songOffset` | 否 | 0 | 歌曲偏移 |
| `musicFolderId` | 否 | 无 | 1.12.0 起，限定音乐文件夹 |

- 官方文档**没有为 `search2`/`search3` 的任何 count 记录上限**。
  明确写「Max 500」的只有 `getAlbumList`/`getAlbumList2` 的 `size`、
  `getRandomSongs` 的 `size`、`getSongsByGenre` 的 `count`。
- **重要修正**：`searchResult3` **没有** `songCount`/`songOffset`/`artistCount`/`albumCount`
  字段。官方 XSD 中它是无属性序列，只含 `artist`、`album`、`song` 三个数组：

  ```xml
  <xs:complexType name="SearchResult3">
      <xs:sequence>
          <xs:element name="artist" type="sub:ArtistID3" minOccurs="0" maxOccurs="unbounded"/>
          <xs:element name="album"  type="sub:AlbumID3"  minOccurs="0" maxOccurs="unbounded"/>
          <xs:element name="song"   type="sub:Child"     minOccurs="0" maxOccurs="unbounded"/>
      </xs:sequence>
  </xs:complexType>
  ```

  `offset`/`totalHits` 只属于**已废弃的 v1 `searchResult`**（`search` 端点）。
  → **客户端无法从 `search3` 响应得知总数**，只能靠「返回条数 < 请求条数」或「空页」终止。

来源：<https://www.subsonic.org/pages/api.jsp>（`search3` 节）；
<https://www.subsonic.org/pages/inc/api/schema/subsonic-rest-api-1.16.1.xsd>（`SearchResult3`）；
<https://opensubsonic.netlify.app/docs/responses/searchresult3/>
置信度：**高**（官方文档 + XSD + OpenSubsonic 规范 + Navidrome 结构体互相印证）。

### 2.2 `search3` 空 query 的行为

**OpenSubsonic 规范明确要求**：

> Servers must support an **empty query** and return all the data to allow clients to
> properly access all the media information for offline sync.

即空 query 返回全库是**规范要求**，用于离线同步。

**Navidrome 的实现**（`master`）：

- `server/subsonic/searching.go`：`sp.query = p.StringOr("query", `""`)`
  —— 默认值是**两个字面引号字符**；`query` 缺省、`query=`、`query=""` 三种写法等价。
- `persistence/sql_search.go` 的 `doSearch`：

  ```go
  q = strings.TrimSpace(q)
  q = strings.TrimSuffix(q, "*")
  // Empty query (OpenSubsonic `search3?query=""`) — return all in natural order.
  if q == "" || q == `""` {
      rowidCore := Select(r.tableName + ".rowid").From(r.tableName).OrderBy(cfg.NaturalOrder)
      return r.executeTwoPhase(sq, results, rowidCore, cfg, options)
  }
  ```

  空串、字面 `""`、以及纯空白（`TrimSpace` 后为空）**都**走「自然顺序返回全部」分支，
  按 `Max`（=`songCount`）与 `Offset`（=`songOffset`）分页。
- 测试覆盖：`server/subsonic/e2e/subsonic_searching_test.go` 有
  `returns all results when query is empty (OpenSubsonic)`；
  `persistence/mediafile_repository_test.go` 验证分页**无重叠、无缺口**，offset 超界返回空页。
- 性能优化：Navidrome v0.63.0 Release Notes 明确写出
  「Full-library synchronization via `search3` (the way clients like Symfonium mirror the whole
  library) is now flat at every offset」，PR #5601 使其在 ~92 万曲目下每个 offset 约 0.1s。

来源：<https://github.com/opensubsonic/open-subsonic-api/blob/main/content/en/docs/Endpoints/search3.md>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/searching.go>；
<https://github.com/navidrome/navidrome/blob/master/persistence/sql_search.go>；
<https://github.com/navidrome/navidrome/releases>（v0.63.0）
置信度：**高**（空串与字面 `""` 有 e2e + 单测；纯空白为源码推导，无专门 HTTP 测试）。

### 2.3 Navidrome 的服务端条数限制

- **`search3` 没有服务端硬上限。** 代码中 `songCount` 直接取自请求
  （`p.IntOr("songCount", 20)`），**不做截断**；配置项也无 `MaxSearchResults` 之类设置，
  `Search` 段只有 `Search.Backend` 与 `Search.FullString`。
- 唯一 500 硬上限在**专辑列表**端点：`server/subsonic/album_lists.go`
  `opts.Max = min(p.IntOr("size", 10), 500)`（仅 `getAlbumList`/`getAlbumList2`）。
- 两个实现细节（**不建议依赖**）：
  - `songCount=0` 会因 `callSearch` 在 `Max == 0` 时短路而返回**空数组**，而不是「无限制」。
  - 负值（如 `songCount=-1`）会绕过短路且各处 `Max > 0` 判断不成立，从而**不加 LIMIT、一次返回全库**。
    这是源码推导，**无文档/测试背书，置信度：中**。
- 另有一个最短长度守卫：`doSearch` 中非空 query 若 `len(q) < 2` 直接返回空（按字节计）。

来源：<https://github.com/navidrome/navidrome/blob/master/server/subsonic/searching.go>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/album_lists.go>；
<https://github.com/navidrome/navidrome/blob/master/persistence/sql_search.go>；
Navidrome 配置文档 <https://www.navidrome.org/docs/usage/configuration/options/>
置信度：**高**（无上限、500 上限位置）；负值行为 **中**。

### 2.4 推荐的全库歌曲分页模式（Navidrome）

```
GET /rest/search3.view?query=""&songCount=500&songOffset=N&artistCount=0&albumCount=0
  &u=...&t=...&s=...&v=1.16.1&c=Hoomy&f=json
```

- 用 `query=""`（字面两个引号）或空 query，逐页递增 `songOffset`，
  直到返回条数 < `songCount` 或返回空页为止。
- `artistCount=0&albumCount=0` 可避免每页顺带查询艺术家与专辑
  （`callSearch` 在 `Max == 0` 时短路，对应数组为空）。
- 这是规范要求、Navidrome 明确实现并专门优化过的路径，**推荐作为「全部歌曲」的主路径**。

### 2.5 其他端点的适用场景与取舍

| 端点 | 返回 | 是否适合「全库歌曲」 |
| --- | --- | --- |
| `search3` 空 query | 歌曲（+艺术家/专辑） | **推荐**；规范要求、有分页连续性测试与专项优化 |
| `getAlbumList2`（`alphabeticalByName`，`size` ≤ 500） | **专辑**列表 | 备选；有 500 上限保证，Navidrome 还返回 `x-total-count` 头（可获取总数），但需对每张专辑再调 `getAlbum`，**N+1 次请求** |
| `getArtists` → `getArtist` → `getAlbum` | 层级 | 最慢（1 + 艺术家数 + 专辑数次请求）。Navidrome 的 `getArtists`/`getArtist` **默认只认 album artist**（除非开启 `Subsonic.ArtistParticipations`） |
| `getIndexes` / `getMusicDirectory` | 艺术家索引 / 模拟目录 | **不推荐**。Navidrome 官方文档明确：不做 browse-by-folder，这两个端点返回「模拟目录树」，格式为 `/Artist/Album/01 - Song.mp3`；`getMusicDirectory` 实际只接受 artist ID 或 album ID |
| `getRandomSongs` | 随机歌曲 | 不适用（随机、有上限） |
| `getSongsByGenre` | 指定风格歌曲 | 必须提供 `genre`，不能用于全库 |

- **不存在**「一次获取全部歌曲」的 Subsonic 或 OpenSubsonic 端点。
  OpenSubsonic 的做法就是澄清 `search3` 空 query 必须返回全量。
- 附注（**非 Subsonic 协议，不建议采用**）：Navidrome 自有原生 API
  `GET /api/song?_sort=&_order=&_start=&_end=` 可带 `x-total-count` 全量取歌，
  但会破坏对其他 Subsonic 系服务端的兼容性。

来源：<https://www.navidrome.org/docs/developers/subsonic-api/>（browse-by-folder 与端点差异说明）；
<https://www.subsonic.org/pages/api.jsp>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/browsing.go>；
<https://github.com/opensubsonic/open-subsonic-api/tree/main/content/en/docs/Extensions>
置信度：**高**。

---

## 3. 收藏（star）

- `star` / `unstar`：核心 Subsonic 端点，自 **1.8.0** 起，**不是** OpenSubsonic 扩展
  （OpenSubsonic `star` 页面无 Extension/Addition 标记）。
  - 参数：`id`（文件/歌曲，或文件夹形式的专辑/艺术家）、`albumId`（专辑）、`artistId`（艺术家）；
    三者均可重复出现以批量操作。
  - **按 ID3 组织媒体的客户端应使用 `albumId`/`artistId`，而不是 `id`。**
  - 成功返回空的 `subsonic-response`。
- `getStarred` / `getStarred2`：同为 1.8.0 核心端点。
  - `getStarred2` 返回 `starred2` 元素，官方 XSD 定义为 `artist`(ArtistID3) + `album`(AlbumID3) + `song`(Child)
    三个数组 —— 即**歌曲/专辑/歌手三个粒度都支持**。
  - `getStarred` 是文件结构版本，字段类型不同，ID3 客户端应使用 `getStarred2`。
- Navidrome 兼容性文档明确列出 `star`、`unstar`、`getStarred`、`getStarred2` 均已支持
  （`star`/`unstar`/`setRating`/`scrobble` 在 Media Annotation 组）。
- 时间戳：`getStarred2` 返回的条目带 `starred` 属性（ISO 8601），可用于展示收藏时间。

来源：<https://www.subsonic.org/pages/api.jsp>（`star`/`unstar`/`getStarred2` 节）；
<https://www.subsonic.org/pages/inc/api/schema/subsonic-rest-api-1.16.1.xsd>（`Starred2` 类型）；
<https://www.subsonic.org/pages/inc/api/examples/starred2_example_1.xml>；
<https://opensubsonic.netlify.app/docs/endpoints/star/>；
<https://www.navidrome.org/docs/developers/subsonic-api/>
置信度：**高**。

---

## 4. 认证与 HTTPS

### 4.1 token 认证算法

自 API 版本 **1.13.0** 起官方推荐 token 认证：

1. 每次请求生成随机 salt（字符串），长度**至少 6 个字符**，作为参数 `s` 发送。
2. 计算 `token = md5(password + salt)`：
   - 结果为 32 个 ASCII 十六进制字符，**小写**；
   - `+` 表示字符串拼接；字符串按 **UTF-8** 编码参与哈希。
3. 作为参数 `t` 发送。

官方示例：password=`sesame`，salt=`c19b2d` →
`token = md5("sesamec19b2d") = 26719a1196d2a940705a59634eb18eab`。

公共参数：`u`（用户名）、`t`、`s`、`v`（客户端实现的协议版本）、`c`（客户端标识）、
`f`（`xml`/`json`/`jsonp`，默认 `xml`）。`p`（明文或 `enc:` 十六进制）自 1.13.0 起
**仅建议用于测试**。

注意：salt 必须**每次请求重新生成**（官方措辞为 "For each REST call, generate a random string"），
不要复用固定 salt。

OpenSubsonic 另定义了 API Key 认证（错误码 `42`/`43`/`44`），以及 `apiKeyAuth` 扩展，
但不是 Hoomy 的必需项。

来源：<https://www.subsonic.org/pages/api.jsp>（Authentication）；
<https://opensubsonic.netlify.app/docs/responses/error/>
置信度：**高**。

### 4.2 HTTPS 与自签证书

- Navidrome **内置** TLS 能力，通过配置项 `TLSCert` / `TLSKey`（`ND_TLSCERT`/`ND_TLSKEY`）
  指定证书与私钥；**默认未启用**（默认值是空，即禁用 TLS）。
  官方安全文档建议「认真考虑放在反向代理（Caddy/Nginx/Traefik/Apache）之后」并配置 SSL，
  并可用 `Address` 限制只监听 `localhost`。
- 默认情况下 Navidrome 以**明文 HTTP** 提供服务（默认端口 `4533`）。
  → **Navidrome 从不强制 HTTPS**，HTTP 明文是被支持的部署方式。
- Subsonic / OpenSubsonic **没有**「客户端信任自签证书」的标准做法或配置项。
  标准做法是客户端使用系统信任库（导入自签 CA 到系统/钥匙串），或服务端使用受信任证书。
- 这与 Hoomy 已定决策一致：`CONTEXT.md` 写明「HTTPS：仅标准证书校验，不支持自签信任」。
- 安全提示：Subsonic 认证凭据（`u`/`t`/`s`）位于**查询字符串**中，明文 HTTP 会暴露凭据，
  因此局域网内也建议启用 HTTPS。另注意 `getOpenSubsonicExtensions` **必须可公开访问**
  （无需认证）。

来源：Navidrome 配置文档 <https://www.navidrome.org/docs/usage/configuration/options/>（`TLSCert`/`TLSKey`）；
Navidrome 安全文档 <https://www.navidrome.org/docs/usage/admin/security/>（Network configuration）；
<https://opensubsonic.netlify.app/docs/endpoints/getopensubsonicextensions/>
置信度：**高**（Navidrome 侧配置与默认值）；「Subsonic 系服务端的自签处理无标准做法」
—— **高**（规范未定义，属客户端 TLS 实现范畴）。

---

## 5. 封面与流

### 5.1 `getCoverArt`

- 参数：`id`（必填）、`size`（可选，缩放到该尺寸，单位像素）。
- 返回：二进制图片；出错时返回 XML（`Content-Type` 以 `text/xml` 开头）。
- OpenSubsonic 澄清：原始 Subsonic 中 `id` 可以指歌曲、专辑或艺术家；
  **对 OpenSubsonic 服务端，`id` 只指 coverArt ID**（即实体 `coverArt` 字段的值，
  如 `Child`、`AlbumID3` 上的 `coverArt`）。
- 实践建议：客户端应使用响应实体里的 `coverArt` 字段值作为 `id`，不要自行拼 `al-`/`ar-` 前缀。
  Navidrome 的 coverArt ID 形如 `al-...`、`ar-...`、`mf-...`，并在多数实体上直接给出。

来源：<https://www.subsonic.org/pages/api.jsp>（`getCoverArt` 节）；
<https://opensubsonic.netlify.app/docs/endpoints/getcoverart/>
置信度：**高**。

### 5.2 `stream`：请求原始流不转码

- 参数：`id`（必填）、`maxBitRate`（kbps，0 表示不限）、`format`、`timeOffset`、`size`、
  `estimateContentLength`、`converted`。
- **不转码的正确写法**：`format=raw`。
  官方文档：自 **1.9.0** 起可使用特殊值 `"raw"` 来禁用转码。
- 其它要点：
  - 不要传 `maxBitRate`（或传 `maxBitRate=0` 表示不限），避免触发降码率。
  - `download` 端点「返回未经转码或降采样的原始媒体数据」，同样可用于获取原始文件；
    Navidrome 的 `download` 还允许传 `id` 为歌曲/专辑/艺术家/歌单，并接受类似 `stream` 的转码参数
    （不传转码参数时返回原始格式，除非开启 `AutoTranscodeDownload`）。
  - `timeOffset` 默认只对视频有效；除非服务端支持 OpenSubsonic `transcodeOffset` 扩展。
  - OpenSubsonic 规定：**`stream` 不得计为一次播放、不得增加播放次数**；
    客户端应调用 `scrobble` 来上报播放。Navidrome 文档也确认「Navidrome does not mark songs
    as played by calls to `stream`, only when `scrobble` is called with `submission=true`」。

来源：<https://www.subsonic.org/pages/api.jsp>（`stream` / `download` 节）；
<https://opensubsonic.netlify.app/docs/endpoints/stream/>；
<https://www.navidrome.org/docs/developers/subsonic-api/>
置信度：**高**。

### 5.3 流 URL 能否直接交给播放器

**可以**，但需把认证参数放进 URL 查询串：

```
http(s)://<host>/rest/stream.view?id=<songId>&format=raw
  &u=<user>&t=<token>&s=<salt>&v=1.16.1&c=Hoomy&f=json
```

- Subsonic 的标准认证是查询参数，不依赖 Cookie 或自定义请求头，
  因此把完整 URL 交给 media_kit（libmpv）等播放器即可直接播放。
- 每次请求应使用新的 salt；因此**播放 URL 不应长期缓存**（含 salt 的 URL 会变化）。
- 若使用 OpenSubsonic `formPost` 扩展则可用 POST 隐藏参数，但这不是通用前提。
- 注意：`f=json` 对二进制端点无意义（不影响返回，返回仍是二进制/错误 XML），可省略。

来源：<https://www.subsonic.org/pages/api.jsp>（Authentication 与 `stream`）；
<https://opensubsonic.netlify.app/docs/extensions/formpost/>
置信度：**高**（认证参数在 URL 上是官方文档示例的做法）。
「media_kit/libmpv 对带查询串 URL 的具体行为」属客户端实现验证范畴，本报告未实测
—— **未能核实**（需在 Hoomy 中实测）。

---

## 6. API 版本兼容与 OpenSubsonic 探测

### 6.1 `v` 应填什么

- 当前最新 Subsonic REST API 版本是 **1.16.1**（对应 Subsonic 6.1.4）。
- **Navidrome 兼容性文档明确声明：Navidrome is currently compatible with Subsonic API v1.16.1。**
- OpenSubsonic 规范：服务端「should support at least **1.14.0**」，
  「not required to support version **1.16.1**, but this is still highly recommended」。
- 结论：Hoomy 的 `v` 填 **`1.16.1`**；这既是 Navidrome 支持的上限，也是 OpenSubsonic 推荐值。
- 版本兼容规则：服务端与客户端主版本号相同且客户端次版本号 ≤ 服务端时才算兼容；
  版本号第三段不参与兼容判断。

来源：<https://www.subsonic.org/pages/api.jsp>（Versions）；
<https://www.navidrome.org/docs/developers/subsonic-api/>；
<https://opensubsonic.netlify.app/docs/subsonic-versions/>
置信度：**高**。

### 6.2 探测 OpenSubsonic 及具体扩展

有三层机制，建议按顺序使用：

1. **响应包体标志**：`subsonic-response.openSubsonic` 为 `true` 表示服务端支持 OpenSubsonic v1。
   同一层还新增了 `type`（服务端名，如 `Navidrome`）与 `serverVersion`（服务端自身版本，
   区别于 `version` 即 API 版本）。客户端可用 `serverVersion` 在服务端升级后重新探测扩展。
2. **`getOpenSubsonicExtensions` 端点**（OpenSubsonic 新增，非 Subsonic）：
   - 路径 `/rest/getOpenSubsonicExtensions.view`，**无参数**；
   - **必须公开可访问**（无需认证）；
   - 返回 `openSubsonicExtensions` 数组，元素形如 `{ "name": "...", "versions": [1, 2] }`。

   因此「检测是否支持同步/逐字歌词」= 在列表中查找 `name == "songLyrics"`，
   并读 `versions`：含 `1` 支持结构化（逐行）歌词，含 `2` 支持 `enhanced=true` 的逐字数据。

3. Navidrome 当前声明的扩展（源码 `server/subsonic/opensubsonic.go`，`master`）：
   `transcodeOffset[1]`、`formPost[1]`、`songLyrics[1,2]`、`indexBasedQueue[1]`、
   `transcoding[1]`、`playbackReport[1]`、`topSongsByArtistId[1]`，
   以及配置了 sonic provider 时的 `sonicSimilarity[1]`。

注意：`getOpenSubsonicExtensions` 本身是 OpenSubsonic 端点。对不支持 OpenSubsonic 的服务端，
应先看 `openSubsonic` 标志，避免直接调用得到未定义错误。

来源：<https://opensubsonic.netlify.app/docs/responses/subsonic-response/>；
<https://opensubsonic.netlify.app/docs/endpoints/getopensubsonicextensions/>；
<https://github.com/navidrome/navidrome/blob/master/server/subsonic/opensubsonic.go>
置信度：**高**。

---

## 7. 对 Hoomy 的落地建议（可执行摘要）

1. **API 版本**：所有请求固定 `v=1.16.1`、`c=Hoomy`、`f=json`。
2. **登录探测**：登录后调用一次 `getOpenSubsonicExtensions`，缓存
   `openSubsonic` 标志、`type`、`serverVersion` 与扩展版本表；服务端 `serverVersion` 变化时重新探测。
3. **歌词**：
   - 支持 `songLyrics` v1 → 用 `getLyricsBySongId?id=<songId>` 取结构化歌词；
     `synced=true` 走逐行 LRC 滚动，`synced=false` 走纯文本静态。
   - 扩展 `versions` 含 `2` → 可选传 `enhanced=true` 以获取逐字 `cueLine`/`cue`（karaoke 高亮）；
     注意 `byteStart`/`byteEnd` 是针对 `cueLine.value` 的 UTF-8 字节闭区间。
   - 否则回退 `getLyrics?artist=&title=`；空 `<lyrics>` 视为「无歌词」。
4. **全部歌曲**：`search3?query=""&songCount=<页大小>&songOffset=<偏移>&artistCount=0&albumCount=0`
   循环分页至空页/短页；不要依赖响应中的总数（不存在）。
5. **收藏**：歌曲用 `star?id=`，专辑用 `star?albumId=`，歌手用 `star?artistId=`；
   读取用 `getStarred2`（三粒度一次返回）。
6. **播放**：`stream?id=<songId>&format=raw`，URL 带 `u/t/s/v/c`；不要传 `maxBitRate`。
   播放上报另调 `scrobble`（`stream` 不计播放）。
7. **封面**：用实体 `coverArt` 字段值调 `getCoverArt?id=&size=`。
8. **HTTPS**：仅标准证书校验；Navidrome 默认明文 HTTP 可用，但凭据在查询串中，建议部署 HTTPS。

---

## 8. 未能核实清单

| # | 条目 | 我查了什么 / 为什么不确定 |
| --- | --- | --- |
| 1 | 未实现 `getLyricsBySongId` 的服务端返回什么错误（HTTP 404？error code 0？） | 查了 Subsonic 错误码表与 OpenSubsonic `getLyricsBySongId`/`error` 文档，规范**未定义**「端点不存在」的错误码；故建议用能力探测而非错误码判断 |
| 2 | `search3` 自然顺序在**并发扫描期间**是否严格稳定 | 源码与提交说明只说按 rowid 有序并使用覆盖索引分页；无关于并发写入期间分页一致性的文档或测试承诺 |
| 3 | Navidrome 负 `songCount`/`size` 返回全库 | 纯源码推导，无测试/文档背书（正文已标「中」） |
| 4 | 空 query 返回全库是 Navidrome 从哪个版本开始的行为 | v0.63.0 明确优化并描述该路径；v0.51.0 已有面向离线客户端的分页优化，但**未能定位该行为首次引入的精确版本** |
| 5 | 闭源 Subsonic 服务端是否有未公开的 `search3` 条数上限 | 只能确认官方文档未记录上限，不能外推为「所有实现都没有」 |
| 6 | media_kit/libmpv 对带认证查询串的 `stream` URL 的实测行为 | 属客户端实现验证，本报告未做运行期实测 |
| 7 | v0.47.0–v0.50.x 是否已（经 TagLib）支持 MP4 `©lyr` / Vorbis `LYRICS` | 属**推断**：那些版本只读通用 `lyrics`/`lyrics-eng` 标签，未跑真实 fixture 验证；可确证的是 v0.51.0 起与 master 的 format-specific 测试已覆盖 flac/m4a/ogg |
| 8 | 「Navidrome 只返回 `xxx`、从不返回 `und`」 | 基于对 `model/`、`core/lyrics/`、`adapters/`、`scanner/` 的全量 grep，**非官方声明** |
| 9 | 发行版镜像/二进制是否与对应 tag 源码完全一致 | 未核实；本报告的版本结论基于 tag 源码与 `git tag --contains` 回溯 |
| 10 | discussion #2982 中引用的「PR #249」编号 | 该编号不成立（#249 是 2021 年另一个 issue）；可考证的剥离时间戳来源是 v0.47.0 的 PR #1379 |

---

## 9. 主要来源清单

Subsonic 官方：
- API 文档 <https://www.subsonic.org/pages/api.jsp>
- REST API 1.16.1 XSD <https://www.subsonic.org/pages/inc/api/schema/subsonic-rest-api-1.16.1.xsd>
- `starred2` 示例 <https://www.subsonic.org/pages/inc/api/examples/starred2_example_1.xml>

OpenSubsonic：
- 站点 <https://opensubsonic.netlify.app/>
- 规范仓库 <https://github.com/opensubsonic/open-subsonic-api>
- 关键页面：`Extensions/songLyrics`、`Endpoints/getLyricsBySongId`、`Responses/structuredLyrics`、
  `Responses/line`、`Responses/lyricsList`、`Responses/subsonic-response`、`Responses/error`、
  `Endpoints/getLyrics`、`Endpoints/search3`、`Responses/searchResult3`、`Endpoints/stream`、
  `Endpoints/getcoverart`、`Endpoints/star`、`Endpoints/getOpenSubsonicExtensions`、
  `Extensions/songLyrics`、`docs/subsonic-versions`

Navidrome：
- 兼容性文档 <https://www.navidrome.org/docs/developers/subsonic-api/>
- 配置选项 <https://www.navidrome.org/docs/usage/configuration/options/>
- 安全文档 <https://www.navidrome.org/docs/usage/admin/security/>
- Releases（版本历史）<https://github.com/navidrome/navidrome/releases>
- 源码：`server/subsonic/{searching,lyrics,opensubsonic,album_lists,browsing}.go`、
  `persistence/{sql_search,sql_search_like,sql_base_repository}.go`、
  `core/lyrics/sources.go`、`adapters/gotaglib/gotaglib.go`、
  `resources/mappings.yaml`、`model/tag_mappings.go`、`model/metadata/metadata.go`

> 配套文件：
> - `docs/research/navidrome-lyrics.md` —— 歌词专题深入版（逐版本源码路径、e2e 测试、`xxx` 语言值等）。
>   本报告第 1 节已合并其结论，该文件保留更细的一手证据链。
> - `.scratch/subsonic-api-research/navidrome-subsonic-api-research.md` —— 全库分页专题笔记
>   （`.scratch/` 已被 `.gitignore` 忽略，不入库），结论已合并进本报告第 2 节。

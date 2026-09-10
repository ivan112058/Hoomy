# 0004 - 歌词按「内容档位」渐进呈现，而非按服务端版本静态判断

日期：2026-09-10　状态：已接受

## 背景

需求原表述为「纯文本静态、逐行 LRC 滚动、逐字 karaoke 高亮，全部支持」。核实后发现三个事实（见 `docs/research/navidrome-lyrics.md`）：

1. `getLyrics`（核心 Subsonic）**会剥离时间戳**，只返回纯文本，拿不到时间轴。
2. 结构化歌词须走 OpenSubsonic `songLyrics` 扩展 `getLyricsBySongId`（Navidrome ≥ 0.51.0）；逐字高亮属该扩展 **v2**，需 `enhanced=true` 且 Navidrome ≥ 0.63.0。
3. 在实测的服务端（0.63.2）上，`songLyrics` 广告 `[1,2]`，但**逐字时间轴取决于曲目内容**：抽查的 12 首全部只有行级 `line[].start`，`cueLine`/`cue` 为空。

第 3 条是决定性的：服务端支持 v2 不等于曲目有逐字数据。「三档全部支持」不是服务端能力问题，而是**内容问题**。

## 决策

歌词按**内容档位**渐进呈现，运行时依实际返回确定档位，不按服务端版本静态分档：

1. 探测 `getOpenSubsonicExtensions` 的 `songLyrics` 版本，据此决定是否发 `enhanced=true`。
2. 拿到 `structuredLyrics` 后：有 `cueLine`/`cue` → 逐字高亮；仅 `line[].start` → 逐行滚动；无 `start` → 纯文本静态。
3. `getLyricsBySongId` 无结果时回退 `getLyrics`（纯文本），再无则不显示歌词。
4. 客户端缓存**解析后**的歌词结构（时间轴），避免每次进歌词页重新解析。

## 后果

- 三档 UI 都要实现，但每首歌自然落在它所属的档位，不需要用户选择。
- 逐字实现须注意 `byteStart`/`byteEnd` 是 **UTF-8 字节偏移的闭区间**，按字符下标切分会使中文歌词错位。
- 服务端（0.63.x）无语言信息时返回 `lang: "xxx"`，客户端应视为「未指定语言」。
- 歌词在**扫描阶段**入库，Navidrome 升级或新增侧车文件后需重新扫描才会更新。

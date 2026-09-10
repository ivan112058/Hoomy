# 0001 - 使用 Subsonic 兼容 API，不在客户端解析音频文件

日期：2026-09-08　状态：已接受

## 背景

Hoomy 的服务端是 Navidrome，提供两套 API：Subsonic 兼容 API（`/rest/*`）与原生 API（`/api/*`）。需求要求读取歌曲的内嵌 metadata、封面、歌词。

## 决策

1. 一律使用 Subsonic 兼容 API。
2. 客户端不下载音频文件自行解析内嵌标签。metadata 取自 API 字段，封面走 `getCoverArt`，内嵌歌词走 `getLyrics` / `getLyricsBySongId`（Navidrome 已在扫描时从文件解析内嵌数据）。
3. 播放请求原始流（`stream` 端点），不转码。

## 后果

- 未来可兼容其他 Subsonic 系服务器（Airsonic、gonic 等）。
- 避免在四平台维护 flac/mp3/m4a 标签解析库；代价是歌词/封面能力受限于服务端解析结果（如旧版 Navidrome 的 `getLyrics` 不返回同步 LRC，需服务端版本 ≥ 0.49 的 `getLyricsBySongId`）。
- 需处理 API 版本与 Navidrome 版本的兼容矩阵。

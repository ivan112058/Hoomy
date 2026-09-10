# 0010 - 播放内核改用 just_audio

日期：2026-09-10　状态：已接受（取代 ADR-0002）

## 背景

ADR-0002 出于「一套播放逻辑、无需为桌面端维护第二套音频栈」的考虑，选定 `media_kit` 为统一内核。此后两件事改变了前提：

1. **平台收缩为 iOS 与 Android TV**（macOS 与 Windows 先后砍掉）。「为桌面端避免第二套音频栈」这一核心理由随之失效。
2. **核实出 `media_kit` 不含后台播放与系统媒体控制**（见 ADR-0008）：解包 1.2.6 检索 `AVAudioSession`/`MPNowPlayingInfoCenter`/`MediaSession` 等零命中，承诺的 `media_kit_os_controls` 至今未发布。媒体会话必须另配 `audio_service`。而 `audio_service` 的官方组合对象是 `just_audio`，与 `media_kit` 的搭配属社区拼接。

此外 `media_kit` 的若干未修 issue 正落在本项目的关键路径上：带 `httpHeaders` 的认证流上 `Media(start:)`/`seek()` 被忽略、不支持按请求动态刷新 header。

## 决策

播放内核改用 **`just_audio`**，媒体会话仍由 `audio_service` + `audio_session` 承担（ADR-0008 不变，只是被封装的内核换成 `just_audio`）。

1. **认证继续走 URL 查询串**，不依赖 `httpHeaders`。
2. **`just_audio` 的原生后端即为各平台最优解**：iOS 走 AVFoundation，Android 走 ExoPlayer/Media3。这与「各平台用各自最优实现」的目标一致，但只维护一套 Dart 逻辑，而不是写两套原生播放器。
3. **不引入 `just_audio_media_kit`**。既然砍掉 macOS，格式一致性的兜底需求消失；若 Android 侧真的暴露 FLAC 缺陷，再把它作为回退方案评估。
4. 先前已定的 `PlayerEngine` 抽象接缝（S2）保留：队列、循环/随机、进度等业务逻辑放在其上的纯 Dart 状态机里，与具体内核解耦。

## 后果

- 省掉 FFmpeg，包体积下降。
- 媒体会话层与内核由同一生态维护，消掉了「两个项目拼接」的风险面。
- **iOS 与 Android 上的实际格式支持必须真机验证**，这是本决策最大的待验证点：曲库 908 首中 769 首为 flac，而 `just_audio` 在 Android 上依赖 ExoPlayer 的格式与设备能力，不再有 FFmpeg 的「一定行」保证。切片 3 必须播真实 `stream?format=raw` URL 验证 flac 与 m4a。
- 由于 `PlayerEngine` 接缝存在，若 `just_audio` 被证伪，回退到 `media_kit` 是替换一个实现，而非架构返工——这正是当初把它做成接缝的价值。
- ADR-0002 中「回退方案是 iOS 单独走 just_audio」的设想被本决策完全反转：现在是全局走 `just_audio`，`media_kit` 成为回退。

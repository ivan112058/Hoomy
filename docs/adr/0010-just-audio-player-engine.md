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
3. **不引入 `just_audio_media_kit`**。该包的作用是把 `just_audio` 的解码后端换成 libmpv，从而在 FFmpeg 路径上获得全格式通吃。当前**不启用**：目标设备为 Android TV 10（API 29），MediaCodec FLAC 解码器可用，无引入理由。它保留为**已知的回退手段**——若真机上 FLAC 被证伪（见下），把它挂在 Android 侧即可，`just_audio` 的 Dart API 不变（见 ADR-0011）。
4. 先前已定的 `PlayerEngine` 抽象接缝（S2）保留：队列、循环/随机、进度等业务逻辑放在其上的纯 Dart 状态机里，与具体内核解耦。

## 待验证的硬约束（切片 3 的验收基准）

**Android 的 FLAC 支持边界已经查清；在目标设备上不构成阻塞**：

- `just_audio` 的 Android 后端是 **AndroidX Media3 ExoPlayer 1.4.1**，使用 `DefaultExtractorsFactory`，**不带 `media3-decoder-flac` 扩展**。
- Media3 官方文档明文：core library 的 FLAC extractor 依赖设备自带的 MediaCodec FLAC 解码器，**「required from API level 27」**，因此 **API < 27 无保证**（Android TV 7.1 = API 25、8.0 = API 26 落在风险区）。
- **目标设备已确认不受此限**：开发与验收用的电视为 Sony KD-55X9500G（BRAVIA 4K UR2），运行 **Android TV 10 = API 29**（安全补丁 2026-02-01），在 API 27 线之上。因此本项目**不以「FLAC 在旧 Android TV 上的兼容性」为设计约束**。
- 平台 FLAC 解码器仍有硬上限（**无多声道、采样率 ≤ 48 kHz、16-bit 为推荐**）。若曲库中存在 hi-res 或多声道 flac，仍走此路径，不保证可靠。
- 已知未修 issue（在目标设备上是否复现**未验证**）：**#440**（FLAC seek 落点偏早 5–30 秒，仅 >3 分钟文件，2021 年开至今 OPEN）；**#868**（部分 FLAC 报 `MediaCodecAudioRenderer: Audio codec error`）；#1017（Android 5 上 FLAC 无声，与本设备无关）。
- 曲库 908 首中 **769 首为 flac**，是主体格式，故以上任一条若在真机复现都会影响主流程。
- **2026-09-14 修正（iOS）**：**#440 已在 iOS 复现并修正**。真机（iPhone / iOS 26.6.2）上 >3 分钟的 flac 拖进度条后，实际出声比上报位置靠前约 30 秒——进度条跑满时歌仍在放、结束时右侧显示 `+0:31`，歌词与进度条据此「对不上」。日志确认上报位置与墙钟 1:1、seek 也如实落到目标，根因是 AVFoundation 默认按估算做「时间 ↔ 字节」映射。修正：`JustAudioPlayerEngine.load` 改用 `ProgressiveAudioSource` 并打开 `DarwinAssetOptions.preferPreciseDurationAndTiming`（映射为 `AVURLAssetPreferPreciseDurationAndTimingKey`）。真机复测多次前后 seek 后位置一致。**Android 仍未验证**（ExoPlayer 侧是另一条路径），`just_audio_media_kit` 回退保留。

**iOS 的阻塞点在 `audio_service` 而非 `just_audio`**（见 ADR-0008 的 #1139）：必须用 `dependency_overrides` 指向 git 才能获得已合并且真机验证的修复，否则锁屏/控制中心在 iOS 上不工作。

**Android TV 侧另有一条未修 issue**：`just_audio` #1179（`MissingPluginException: ... dispose`，**mainly on Android TV devices**，生产环境 Crashlytics 上报，维护者称无法复现与调查）。这是本项目**唯一平台**上的一处未解释崩溃风险，切片 3 与切片 14 都需在真机观察。

## 后果

- 省掉 FFmpeg：iOS 体积增量 ≈0（`just_audio` 无第三方二进制，全调系统框架），Android ≈3.1 MiB 且与 ABI 无关；而 `media_kit` 为 iOS ≈6.2 MiB、Android ≈6.3 MiB/ABI。
- 媒体会话层与内核由同一生态维护，消掉了「两个项目拼接」的风险面。
- `just_audio` 具备 `PlayerEngine` 接缝所要求的可替换性，这使本决策**可逆**：若 Android FLAC 被证伪，回退到 `media_kit` 是替换一个实现，而非架构返工。这正是当初把接缝做出来的价值。
- ADR-0002 中「回退方案是 iOS 单独走 just_audio」的设想被本决策完全反转：现在是全局走 `just_audio`，`media_kit` 成为回退。
- 生态一致性作为旁证：抽样 12 个同类开源客户端（Subsonic/Navidrome/Jellyfin）中 11 个使用 `just_audio`；且 Finamp 把 token 放在 query string 并注明「just_audio 对 header 支持曾有 HLS 问题」，与本项目的 Subsonic 认证形态完全同形。

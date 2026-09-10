# 0008 - 后台播放与系统媒体控制交给 audio_service + audio_session

日期：2026-09-10　状态：已接受

## 背景

ADR-0002 选定 `media_kit` 为统一播放内核。核实后发现一个会改变架构的事实：**`media_kit` 只负责解码与播放，不提供后台播放、锁屏/控制中心信息、媒体通知与媒体键支持**。解包 1.2.6 全包检索 `AVAudioSession`/`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`/`MediaSession`/`SMTC`/`MPRIS`/`audio_service`/`audio_session` **零命中**，包内不存在 android/ios/macos/windows 原生目录；维护者明确表示「We do not have our own OS controls plugin at the moment」，承诺中的 `media_kit_os_controls` 至今未发布。

而「后台播放与锁屏控制」是本项目 MVP 必含项。因此必须引入第三方媒体会话层，这不是可选优化。

## 决策

`media_kit` 只做音频解码与播放；媒体会话与系统集成交给 `audio_service` + `audio_session`。

1. **`audio_service` 持有播放状态的权威**。其 `AudioHandler` 封装 `media_kit` 的 `Player`；UI 从 `audio_service` 暴露的流读取播放状态，不直接读 `media_kit`。
2. **`audio_session` 负责音频会话与打断**。在 `MediaKit.ensureInitialized()` **之后**配置 `AudioSessionConfiguration.music()`；必须自行订阅并处理 `interruptionEventStream`（来电/其他 App 抢占）与 `becomingNoisyEventStream`（耳机拔出 → `pause()`）——`media_kit` 不订阅这些流。
3. **认证一律走 URL 查询串**（Subsonic 原生方式），**不依赖 `httpHeaders`**。`media_kit` 有未修 issue：带 `httpHeaders` 的流上 `Media(start:)` 与 `seek()` 被忽略，且不支持按请求动态刷新 header。查询串经实测原样透传。
4. **曲目身份由客户端持有**。`media_kit` 的事件流不含 title/artist，队列须自行维护曲目元数据，并通过 `audio_service` 的 `MediaItem` 推送给系统。
5. **平台范围**：Android TV、iOS、macOS 三平台均由 `audio_service` 覆盖（其原生实现含 android 与 darwin）。**Windows 已砍掉**，故不涉及桌面第二套媒体会话方案。

## 后果

- `audio_service` 改变了播放状态的持有位置：切片 3–8 都要建立在「`AudioHandler` 是播放状态权威」之上，不能各自直接持有 `Player`。
- **iOS 是高风险项，且风险在 `audio_service` 一侧而非 `media_kit`**：已知 issue 包括「iOS 锁屏后音频停止」（OPEN 两年余未修）与「media_kit + audio_service 在 iOS 不工作」（Android 正常，维护者关闭但无修复）。因此 iOS 上线前必须真机验收三条路径：**锁屏、切到其他 App、锁屏超过 1 分钟**。
- 避免把服务端放在「仅允许 TLS 1.3」的终端后面：`media_kit` 内置 Mbed TLS 缺 TLS 1.3 client，Android/iOS 会握手失败。局域网 HTTP 场景不受影响。
- `audio_service` 与 `media_kit` 职责不重叠，二者不冲突；`media_kit` 作者自己的 Harmonoid 正是 `audio_service` + `audio_session` + `media_kit` 的组合。

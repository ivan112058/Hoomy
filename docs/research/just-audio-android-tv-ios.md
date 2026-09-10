# just_audio 生态核实报告（聚焦 Android TV + iOS）

调研日期：2026-09-10。范围：Hoomy 播放内核从 `media_kit` 改为 `just_audio` 的可行性核实。
平台范围：**仅 iOS、Android TV**（macOS / Windows 已砍掉，本报告不再展开）。
所有版本号来自 pub.dev API 实查；所有体积数字为本次直接测量 pub.dev / GitHub Release 产物所得，方法随文标注。

---

## 组前：定版信息（一手来源：pub.dev API，2026-09-10 实查）

| 包 | 最新稳定版 | 发布日期 | likes | points | downloads/30d | 平台 |
|---|---|---|---|---|---|---|
| `just_audio` | **0.10.6** | 2026-06-29 | 4147 | 150/160 | 1,095,728 | android / ios / macos / web |
| `audio_service` | **0.18.19** | 2026-06-29 | 1331 | 140/160 | 204,802 | android / ios / macos / web |
| `audio_session` | **0.2.4** | 2026-06-29 | — | — | — | android / ios / macos / web |
| `just_audio_background` | **0.0.1-beta.17** | 2025-05-13 | 366 | 130/160 | 45,724 | android / ios / macos / web |
| `just_audio_media_kit` | **2.1.0** | 2025-04-13 | 19 | 150/160 | 22,081 | 全平台（纯 Dart） |
| `media_kit` | **1.2.6** | 2025-12-13 | 912 | 140/160 | 334,407 | 全平台 |

来源：`https://pub.dev/api/packages/<包名>`、`https://pub.dev/api/packages/<包名>/score`

**关键版本陷阱（本次独立核实）**：`audio_service` 的 git `minor` 分支上已有 `0.18.20` 的 CHANGELOG 条目，但 **0.18.20 未发布到 pub.dev**。
证据：① pub.dev API 的 `versions` 列表中最高为 `0.18.19`；② 从 pub.dev 下载的 `audio_service-0.18.19.tar.gz` 内的 `CHANGELOG.md` 首条即 `## 0.18.19`（若 0.18.20 已发布，其归档首条会是 0.18.20）。
这条对第 4 节（iOS）至关重要。置信度：**高**。

置信度标记约定：**高** = 官方文档 / 官方源码 / 官方 API 直接读出；**中** = 官方 issue 追踪器中的具体条目（真实存在但有单方陈述成分）；**低** = 社区博客、二次转述。

---

## 一、Android 上 just_audio 的 flac / mp3 / m4a 支持

### 1.1 底层是 AndroidX Media3 ExoPlayer 1.4.1（不是旧版 `com.google.android.exoplayer`）

解包 `just_audio-0.10.6.tar.gz`（pub.dev 发布归档）后的 `android/build.gradle.kts`：

```
val exoplayerVersion = "1.4.1"
implementation("androidx.media3:media3-exoplayer:$exoplayerVersion")
implementation("androidx.media3:media3-exoplayer-dash:$exoplayerVersion")
implementation("androidx.media3:media3-exoplayer-hls:$exoplayerVersion")
implementation("androidx.media3:media3-exoplayer-smoothstreaming:$exoplayerVersion")
```

`android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java` 全部 import 自 `androidx.media3.*`（`ExoPlayer`、`MediaItem`、`PlaybackException` 等），异常类型也映射为 `ExoPlaybackException.type`。
来源：<https://pub.dev/api/archives/just_audio-0.10.6.tar.gz>　置信度：**高**

### 1.2 just_audio 用的是默认 extractor 工厂，**不打包含 FLAC 解码扩展**

`AudioPlayer.java:613-614`：

```java
private DefaultExtractorsFactory buildExtractorsFactory(Map<?, ?> options) {
    DefaultExtractorsFactory extractorsFactory = new DefaultExtractorsFactory();
```

即只使用 Media3 core 的 `FlacExtractor`（输出 FLAC 帧），**没有**引入 `media3-decoder-flac`（`LibflacAudioRenderer`，需 NDK 编译 libFLAC）。
来源：同上发布归档；`media3-decoder-flac` 的作用见 <https://github.com/androidx/media/blob/main/libraries/decoder_flac/README.md>　置信度：**高**

### 1.3 mp3 / m4a：无 API level 风险

Android 官方格式表（`Format / Encoder / Decoder / File Types`）：

- `MP3` → Decoder **YES**（无版本限制）
- `AAC LC` → Decoder **YES**；容器 `• MPEG-4 (.mp4, .m4a)`

来源：<https://developer.android.com/media/platform/supported-formats>（本次直接解析页面表格）　置信度：**高**

### 1.4 flac：受 **API level 27** 限制——这是最关键的一条

Media3 官方「Supported formats → Progressive」页对 FLAC 的脚注原文：

> FLAC | YES | Using the FLAC library or the FLAC extractor in the ExoPlayer library***
> \*\*\* The FLAC library extractor outputs raw audio, which can be handled by the framework on all API levels. The FLAC extractor in the ExoPlayer library outputs FLAC audio frames and so relies on having a FLAC decoder (for example, a `MediaCodec` decoder that handles FLAC (**required from API level 27**), or the FFmpeg library with FLAC enabled).

因为 just_audio 用的是 **core library 的 FLAC extractor**，所以：

- **API ≥ 27 的设备**：有系统 `MediaCodec` FLAC 解码器可用，可播。
- **API < 27 的设备**：无保证；要么设备厂商额外提供 FLAC MediaCodec，要么应用自带 FLAC library 扩展（just_audio 不带），否则播放失败。

来源：<https://developer.android.com/media/media3/exoplayer/supported-formats>（本次从页面 HTML 中提取到该脚注原文）　置信度：**高**

补充事实：Android **平台自身**的 FLAC 解码器从 Android 3.1+（API 12）就有，但有硬性能力上限——官方原文：

> FLAC | Android 4.1+（编码器）/ Android 3.1+（解码器）| • FLAC (.flac) • MPEG-4 (.mp4, .m4a, Android 10+) • Matroska (.mkv) | Mono/Stereo (no multichannel). Sample rates up to 48 kHz（44.1 kHz 更推荐）… 16-bit recommended; no dither applied for 24-bit.

即：**平台 FLAC 解码器不支持多声道、采样率上限 48 kHz、推荐 16-bit**。hi-res FLAC（如 96 kHz/24-bit）在 MediaCodec 路径上不可靠。
来源：<https://developer.android.com/media/platform/supported-formats>　置信度：**高**

### 1.5 Android TV 的 API 下限，与「API < 27」风险的实际交集

- Android TV 应用要求 **API 21+**（官方 Start 文档：「create a project that targets Android 5.0 (API level 21) or higher」）。
- 因此你担心的「API < 21」对 Android TV **不成立**（Android TV 从 Android 5.0 起）。
- 但「API < 27」对 Android TV **成立**：Android TV 版本对应 API 为 7.1 = API 25、8.0 = API 26、9 = API 28、10 = API 29、11 = API 30、12 = API 31、14 = API 34。**Android TV 7.1（API 25）与 8.0（API 26）落在 < 27 区间**；Android TV 9（API 28）及以上满足 API 27+ 条件。

来源：<https://developer.android.com/training/tv/start/start>（API 21+）；API level 对照为 Android 版本号公开常识　置信度：**中**（TV 版本↔API 的映射未在单一官方页面上逐条列出）

### 1.6 Android 侧已知的 FLAC issue（都是真实、未修）

| Issue | 状态 | 内容 | 来源 |
|---|---|---|---|
| **#1017** | **OPEN**，2023-07-07，label `bug`/`1 backlog` | Android 5 设备播 FLAC：能读出时长、进度在走，但**完全没有声音**；同一设备播 mp3 正常 | <https://github.com/ryanheise/just_audio/issues/1017> |
| **#814 / #868** | #814 closed、**#868 OPEN**（2022-11 → 2023-07） | Android 上部分曲目报 `MediaCodecAudioRenderer: Audio codec error` / `IllegalStateException`。报告者实测：**升级 ExoPlayer 版本无效**，最终从 Auxio 项目提取 ExoPlayer 的 **FLAC extension（libflac 编成 .so）** 引入后才正常。维护者只升级了 ExoPlayer（分支 `feature/upgrade_exoplayer`），**未把 FLAC 扩展并入 just_audio** | <https://github.com/ryanheise/just_audio/issues/814>、<https://github.com/ryanheise/just_audio/issues/868> |
| **#440** | **OPEN**，2021-07-05，更新至 2024-10-13，**22 条评论** | 「Seek position of Flac audio actually leads to an earlier position」：>3 分钟的 FLAC 拖到靠后位置，实际落点早 5–30 秒；进度条到头了音乐还在放。复现工程指向官方 example | <https://github.com/ryanheise/just_audio/issues/440> |
| **#1565** | OPEN，2025-11-30 | FLAC 播到结尾报 `flac: invalid sync code` 并中断、不播下一首。**注意：该用户的日志前缀是 `MPV:`，即它跑的是 `just_audio_media_kit` + libmpv，不是 just_audio 原生后端** | <https://github.com/ryanheise/just_audio/issues/1565> |

**未能核实**：just_audio 官方 README **没有格式支持表**。README 关于格式只有一句「Different platforms support different audio formats and encodings. For a list, see this StackOverflow answer」，指向 <https://stackoverflow.com/questions/73557707>；该页被 Cloudflare 拦截，本次未能读取其内容。因此「just_audio 官方格式支持表」这一项**不存在**，上述格式结论全部来自 Media3 / Android 官方文档与源码。
来源：<https://raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/README.md>　置信度：**高**（指「README 无格式表」这一事实）

### 1.7 本节结论（Android 格式）

- `mp3` / `m4a`：**无风险**，全 API 覆盖。
- `flac`：**MP3/M4A 之外唯一的风险点，且是你曲库的主力**（769/908）。风险有三层：
  1. **API < 27 无保证**（Media3 官方明文），Android TV 7.1/8.0 命中；
  2. **平台解码器能力上限**：无多声道、≤48 kHz、推荐 16-bit；
  3. **已有的未修 issue**：部分设备/文件直接报解码错误（#814/#868），社区解法是自行引入 ExoPlayer FLAC extension，just_audio 未内置。
- 相对地，`media_kit` 走 FFmpeg，不受设备解码器限制（这是 ADR-0002 选它的核心理由，至今未被推翻）。

---

## 二、just_audio + audio_service 在 Android 上的后台播放

### 2.1 官方推荐关系：是（双向互指）

- `audio_service` README：「a music player app might implement these callbacks using **just_audio** to render the audio」；并在「Can I make use of other plugins」中再次点名 `just_audio`。
- `just_audio` README 在后台音频一节列出两个官方方案：`just_audio_background`（简单场景）与 `audio_service`（进阶场景）。
- `just_audio_background` 本身依赖 `audio_service`（pubspec 实查：deps 含 `audio_service`）——即「简单方案」也是 audio_service 的一层封装。

来源：<https://raw.githubusercontent.com/ryanheise/audio_service/minor/audio_service/README.md>、<https://raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/README.md>、<https://pub.dev/api/packages/just_audio_background>　置信度：**高**

### 2.2 Android Manifest 完整配置（audio_service README 原文，逐条照抄）

**权限**：

```xml
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<!-- ALSO ADD THIS PERMISSION IF TARGETING SDK 34 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
```

**Activity**：把现有 `<activity>` 的 `android:name` 改为 `com.ryanheise.audioservice.AudioServiceActivity`（或让自定义 Activity 继承 `AudioServiceActivity` / `AudioServiceFragmentActivity`）。

**Service**：

```xml
<service android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true" tools:ignore="Instantiatable">
  <intent-filter>
    <action android:name="android.media.browse.MediaBrowserService" />
  </intent-filter>
</service>
```

**Receiver（媒体键）**：

```xml
<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true" tools:ignore="Instantiatable">
  <intent-filter>
    <action android:name="android.intent.action.MEDIA_BUTTON" />
  </intent-filter>
</receiver>
```

来源：<https://raw.githubusercontent.com/ryanheise/audio_service/minor/audio_service/README.md>（Android setup 一节）　置信度：**高**

### 2.3 Android 12 / 14 / 15 的前台服务限制：会踩，但都可预期

- **Android 12**：后台重启前台服务会抛 `ForegroundServiceStartNotAllowedException`。README 给两条解法：`AudioServiceConfig.androidStopForegroundOnPause = false`（暂停时不退出前台），或引导用户关闭电池优化。
- **Android 14（targetSdk 34）**：必须声明 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限 + `foregroundServiceType="mediaPlayback"`（README 已覆盖）。
- **Android 15 新增**：① `mediaPlayback` 类型前台服务**不允许由 BOOT_COMPLETED 广播启动**；② 「6 小时超时」只适用于 `mediaProcessing` / `dataSync` 类型，**不适用于 `mediaPlayback`**。Hoomy 由用户手动启动播放，① 不命中；② 不影响。

来源：audio_service README；<https://developer.android.com/about/versions/15/changes/foreground-service-types>（本次抓取原文确认 mediaPlayback 条目与 6 小时条目归属）　置信度：**高**

### 2.4 Android 侧已知未修 issue（与本项目相关的）

| Issue | 状态 | 内容 |
|---|---|---|
| **#1165** | **OPEN**，2026-07-26 | `AudioService.onCreate()` 中 `getFlutterEngine()` 阻塞主线程加载 Dart snapshot，**后台服务启动时 ANR**。0 条评论，无修复 |
| **#1062** | OPEN，2024-02-25，更新至 2026-02-22 | 目标 API 29 时，Android 14 通知栏播放键不工作 |
| **#1082** | OPEN，2024-07-19 | `stop` 后媒体通知不消失 |
| **#932** | OPEN，2022-05-06，27 条评论 | 三星设备锁屏/后台被暂停（`ForegroundServiceStartNotAllowedException`） |
| **#996** | OPEN，2023-02-26，更新至 2026-07-06 | `ForegroundServiceStartNotAllowedException: mAllowStartForeground false` |
| **#1115** | OPEN，2025-04-02，11 条评论 | OnePlus OxygenOS 上的异常 |

来源：GitHub Issues API 逐条读取　置信度：**中**（issue 状态与标题为事实，现象为单方报告）

统计口径参考：`repo:ryanheise/audio_service is:issue is:open` → **178** 条。

---

## 三、Android TV 特有行为

### 3.1 Flutter 是否官方支持 Android TV：**没有**

`https://docs.flutter.dev/reference/supported-platforms` 页面对 `Android TV` 与 `tvOS` 的出现次数均为 **0**。Flutter 未把 Android TV 列为官方支持平台。
来源：<https://docs.flutter.dev/reference/supported-platforms>（本次字符串计数）　置信度：**高**

### 3.2 Android TV 应用的官方硬性要求

- 必须 **API 21+** 目标。
- 必须有一个声明 `CATEGORY_LEANBACK_LAUNCHER` 的 launcher activity（官方原文：「An application intended to run on TV devices must declare a launcher activity for TV in its manifest. It uses a `CATEGORY_LEANBACK_LAUNCHER` intent filter… lets Google Play identify it as a TV app」）。
- 必须提供 **home screen banner**：320×180 px、放在 `drawable-xhdpi`、`<application android:banner="@drawable/banner">`。
- 官方 checklist 还提醒：媒体播放类 App 需要考虑 **Ambient Mode**（屏保）问题。

来源：<https://developer.android.com/training/tv/start/start>、<https://developer.android.com/training/tv/publishing/checklist>　置信度：**高**

### 3.3 Flutter 在 Android TV 上的真实先例（同款 Manifest 写法）

`cuiocean/ZY-Player-TV`（199★，Flutter 写的 Android TV 应用）的 `AndroidManifest.xml`：

```xml
<application android:banner="@drawable/banner" ...>
  <activity android:name=".MainActivity" ...>
    <intent-filter>
      <action android:name="android.intent.action.MAIN"/>
      <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
      <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
```

即：**同一个 activity 同时挂 LEANBACK_LAUNCHER 与 LAUNCHER 两个 category**，`banner` 挂在 `<application>` 上。这与 audio_service 要求「把 MainActivity 换成 `AudioServiceActivity`」并不冲突——把 leanback intent-filter 加在 `AudioServiceActivity` 上即可。
来源：<https://github.com/cuiocean/ZY-Player-TV>（`zy_player_tv/android/app/src/main/AndroidManifest.xml`，2021 年项目；视频类，未用音频库）　置信度：**中**

**未能核实**：本次未找到任何在 Android TV 上使用 `just_audio`（或 `audio_service`）的开源 Flutter **音乐** App 先例。GitHub 仓库搜索 `flutter android tv leanback`、`flutter subsonic`、`flutter navidrome` 的结果中，TV 项目全是视频/launcher 类。

### 3.4 TV 上的「媒体通知」= launcher 的 Now Playing 卡片，由 MediaSession 驱动

Android 官方 Now Playing 文档原文：

> TV apps that play audio may continue to do so after the user returns to the home screen… To do so, the app must provide a Now Playing card on the home screen.
> Whenever an active **MediaSession** is present, the Android framework displays a Now Playing card on the home screen. The card includes media metadata such as album art, title, and app icon.
> After you implement a media session, set the session to active, and request audio focus, the Now Playing card appears.

并附注：卡片只在 media session 带 `FLAG_HANDLES_TRANSPORT_CONTROLS` 时显示（该 flag 在 API 26 起弃用，老设备可能仍需要）。

**audio_service 是否满足**：是。Android 源码中确有激活/去激活调用：
`AudioService.java:707-708`、`742-743`、`890-891` → `if (!mediaSession.isActive()) mediaSession.setActive(true);`，`747-748` → `setActive(false)`。
且 `FLAG_HANDLES_TRANSPORT_CONTROLS` 由 `MediaSessionCompat` 的 transport control 处理路径覆盖（audio_service 注册了 play/pause/skip 等回调）。

来源：<https://developer.android.com/training/tv/playback/now-playing>、`audio_service-0.18.19` 发布归档 `android/src/main/java/com/ryanheise/audioservice/AudioService.java`　置信度：**高**

### 3.5 D-pad / 媒体键：系统会自动路由到 MediaSession

Android 官方 TV 控制器文档原文：

> When the user is watching media… If your app is controlling a MediaSession, use a MediaControllerAdapter to call one of the MediaControllerCompat.TransportControls methods shown in the table. Note that the selection buttons act as Play or Pause buttons in this context.
> KeyEvent 映射：`BUTTON_SELECT / BUTTON_A / ENTER / DPAD_CENTER / NUMPAD_ENTER` → `play()`；`BUTTON_R1` → `skipToNext()`；`BUTTON_L1` → `skipToPrevious()`；`DPAD_LEFT` → `rewind()`；`DPAD_RIGHT` → `fastForward()`
> Note: When you use a MediaSession, **don't override the handling of media-specific buttons**, such as `KEYCODE_MEDIA_PLAY` or `KEYCODE_MEDIA_PAUSE`. The system automatically triggers the appropriate `MediaSession.Callback` method.

含义：TV 遥控器的媒体键路径**不需要应用自己做 D-pad 媒体键分发**，交给 MediaSession 即可；audio_service 已实现 MediaSession.Callback 与 `MediaButtonReceiver`（manifest 里那个 receiver）。
来源：<https://developer.android.com/training/tv/get-started/controllers>　置信度：**高**

**UI 焦点层**（方向键在列表/网格中移动）是 Flutter 侧的另一件事：Flutter 没有官方 TV focus 方案，社区有 `dpad` 包（**3.0.0**，2026-06-12，「Production-grade D-pad navigation for Flutter TV apps」）。
来源：<https://pub.dev/api/packages/dpad>　置信度：**中**（包存在与描述为事实；是否必需取决于 Hoomy 的 UI 复杂度）

### 3.6 Android TV 上 just_audio 的已知 issue（生产环境实测）

| Issue | 状态 | 内容 |
|---|---|---|
| **#1179** | **OPEN**，2024-01-26，更新至 2024-03-15，4 条评论 | 「No implementation found for plugin dispose method **mainly on Android TV devices**」。症状：`MissingPluginException: No implementation found for method dispose on channel com.ryanheise.just_audio.methods.`，来自生产 Firebase Crashlytics，**偶尔发生、无法复现**。维护者回复「I cannot tell… Then I don't have any way to investigate this」，**无修复、无结论** |

来源：<https://github.com/ryanheise/just_audio/issues/1179>　置信度：**中**

`audio_service` 侧：Android 源码中**没有**任何 TV / leanback / `isTv` 分支（grep 全文无命中），也没有 TV 专属 issue（`repo:ryanheise/audio_service is:issue "Android TV"` 仅 3 条命中，且全是 Windows/Linux、Android Auto、Manifest 报错的误匹配，全部 closed）。即：**没有 TV 专属适配，也没有 TV 专属故障报告**。
来源：`audio_service-0.18.19` 发布归档 android 源码 grep；GitHub Issues 搜索　置信度：**高**

---

## 四、iOS 上 just_audio + audio_service 的后台播放可靠性

### 4.1 iOS 需要的配置

| 配置 | 内容 | 来源 |
|---|---|---|
| `Info.plist` | `UIBackgroundModes` → `<array><string>audio</string></array>` | audio_service README「iOS setup」 |
| 音频会话 | `audio_session` 包，`AudioSessionConfiguration.music()`；在**所有其他音频插件加载之后**配置 | audio_service / just_audio README「Configuring the audio session」 |
| 明文 HTTP | 若访问非 HTTPS URL，或使用依赖本地代理的功能（headers / caching / stream source），`Info.plist` 加 `NSAppTransportSecurity` → `NSAllowsArbitraryLoads = true` | just_audio README「Platform specific configuration → iOS」 |
| 最低 iOS | `audio_service` 0.18.20 起最低 iOS 提升到 **13.0**（0.18.19 及以前的支持范围见其 Podfile 说明） | audio_service CHANGELOG 0.18.20（git `minor`）+ issue #1139 维护者评论 |

来源：<https://raw.githubusercontent.com/ryanheise/audio_service/minor/audio_service/README.md>、<https://raw.githubusercontent.com/ryanheise/just_audio/minor/just_audio/README.md>　置信度：**高**

### 4.2 【最高价值发现】audio_service #1139：已发布版本在 iOS 上**不上报播放状态**

| 项 | 内容 |
|---|---|
| 标题 | Playing state is not being reported to iOS versions >= 13.0 |
| 状态 | **OPEN**，创建 2025-09-08，最后更新 2026-07-06，8 条评论 |
| 影响版本 | **已发布的 0.18.18**（报告者以 tag v0.18.18 复现）；0.18.19 尚未包含修复 |
| 症状 | iOS 不知道当前播放状态 → ① 锁屏 / 控制中心无媒体控件；② Dynamic Island 不显示；③ **Apple CarPlay 不工作**；④ 其他 App 开始播放时**不会暂停**本 App |
| 根因 | `darwin/audio_service/.../AudioServicePlugin.m` 中一处被 `#if TARGET_OS_OSX` 守卫包住的代码路径（报告者定位到具体行） |
| 修复 | PR **#1140**；维护者 2026-07-01 合并进 `minor` 分支（即未发布的 0.18.20 的 CHANGELOG 首条：*Fix AudioServicePlugin not reporting playing state to iOS versions >= 13.0 (@marckornberger)*） |
| 真机验证 | 2026-07-06，用户 `HazAnwar` 在**实体 iPad / iPadOS 26.5.2** 上确认修复生效（此前他用 `dependency_overrides` 指向 `marckornberger` 的 fork 验证过真机可用） |
| 发布状态 | **截至 2026-09-10，0.18.20 未发布到 pub.dev**（pub.dev API 实查 latest = 0.18.19；0.18.19 发布归档的 CHANGELOG 首条即 0.18.19） |
| 绕过方式 | pubspec 里 `dependency_overrides` 指向 `minor` 分支或 PR #1140 的 commit |

来源：<https://github.com/ryanheise/audio_service/issues/1139>（正文 + 8 条评论逐条读取）、<https://pub.dev/api/packages/audio_service>　置信度：**高**

**这条的实际意义**：换 just_audio 后 iOS 上「锁屏/控制中心」这个 MVP 必含项，在 pub.dev 稳定版（0.18.19）上**极可能直接不工作**，且不是配置问题、不是真机偶发，而是代码里一处确定的状态上报缺陷。好消息是修复已存在且有真机验证，属于**可立即绕过**的问题，而非架构缺陷。

### 4.3 iOS 其余未修 issue（锁屏 / 切 App / 后台）

| Issue | 状态 | 内容 |
|---|---|---|
| **#993** | **OPEN**，2023-01-24，更新至 2024-12-20，8 条评论 | 「audio in background freeze if you load a new file and play」：**iOS 16.x 上，App 在后台时加载新曲目并播放，音频卡死**；iOS 14/15 正常。提供复现工程。评论中分析：`completed` 后广播 `idle` 状态可能关闭了 iOS 16 的音频会话 |
| **#1034** | OPEN，2023-08-03 | 「iOS not showing controls in Notification center or lock screen」 |
| **#1153** | OPEN，2026-01-24，更新至 2026-04-19 | 「iOS lock screen not showing song metadata (**audio plays fine**)」——音频正常，仅元数据不显示 |
| **#917** | OPEN，2022-03-07，25 条评论 | 锁屏/控制中心 play/pause 按钮偶发**变灰**（报告场景含 flutter_tts） |
| **#724** | OPEN，2021-06-11，11 条评论 | 「iOS control center issue」 |
| **#1047** | OPEN，2023-11-09 | `just_audio_background` 在 iOS 上无法释放后台音频服务 |
| **#1094** | OPEN，2024-10-02 | Xcode 16 下 iOS 没有 play/pause 按钮 |

来源：GitHub Issues API 逐条读取　置信度：**中**

**数量口径**：`repo:ryanheise/audio_service is:issue is:open ios` → **90** 条（全文匹配，非精确标签计数）；其中 `label:bug` 的 33 条。`repo:ryanheise/just_audio is:issue is:open ios` → 169 条（同样为全文匹配，含大量无关误匹配）。

**关于 ADR-0008 中「iOS 锁屏后音频停止（OPEN 两年余未修）」这一表述的核实结论**：本次**没有找到**一条标题/正文精确为「iOS 锁屏后音频停止」的 issue。最接近的是 #993（**iOS 16 后台加载新曲目时卡死**，2023 年开、至今 OPEN，已两年半）。ADR-0008 的说法方向正确，但更精确的表述应是 #993 的场景（后台切歌卡死），而不是泛化的「锁屏即停」。置信度：**中**（基于搜索覆盖；不排除存在措辞不同的同义 issue）

### 4.4 与 `media_kit` + `audio_service` 的同类 issue 对比

| 维度 | just_audio + audio_service | media_kit + audio_service |
|---|---|---|
| iOS 后台专属 issue | **#1139 OPEN**（已发布版不上报播放状态 → 锁屏/CarPlay 全废；**修复已合并、真机验证通过、未发版**）；#993 OPEN（后台切歌卡死）；#1034/#1153/#917/#724 OPEN（控件/元数据） | **media-kit#1227「Background audio playback (audio_service) on iOS not working.」** 2025-07-22 开，2026-06-24 **closed as completed**，全程**仅 1 条评论**（且来自第三方用户，非维护者） |
| 关闭时的实际状态 | 修复存在于 git，可用 `dependency_overrides` 立即获得 | 关闭理由为用户自行解释「iOS 对后台音频很严格，进入后台会暂停约 1 秒，iOS 便认为播放结束」；**无代码修复** |
| 内核是否具备会话语义 | **具备**：`just_audio` 直接依赖 `audio_session` 并激活会话；`audio_service` 的 darwin 实现直连 `AVAudioSession` / `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`（本次解包核实） | **不具备**：`media_kit` **1.2.6** 的 `lib/` 中 `AVAudioSession` / `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` / `MediaSession` / `audio_service` / `audio_session` 命中数为 **0**（本次独立 grep 核实，全仓 0 命中） |
| 承诺的 OS 控制插件 | N/A | `media_kit_os_controls` 在 pub.dev **404**（本次实查） |
| 仓库 issue 总量 | audio_service open **178**；just_audio open **295** | media_kit open **332**；其中提及 audio_service 的 open issue **0**（3 条全 closed） |

**严重程度结论（事实层面）**：

- `media_kit` 的问题是**结构性的**：内核完全不含音频会话/系统媒体控制语义，iOS 后台播放依赖第三方（audio_service）去「外挂」，而 iOS 的严格后台策略会让这个外挂失效（media-kit#1227 的关闭评论即为该机制的描述），且官方未提出修复计划。
- `audio_service` 的问题是**代码缺陷**：状态上报逻辑在某条 iOS ≥13 分支上没生效；修复已合并、已在真机验证，只是尚未发版。可以用 `dependency_overrides` 今天就拿到。
- 两者都**不是零风险**，但性质不同：一个是「缺口 + 无修复」，一个是「有修复 + 未发版」。

---

## 五、HTTP 串流与认证（query string / httpHeaders / seek）

### 5.1 带 query string 的 URL：**支持**（URI 原样透传）

- Android：`AudioPlayer.java:640/646/653` → `MediaItem.Builder()...setUri(Uri.parse((String)map.get("uri")))`，URI（含 query）原样交给 ExoPlayer。
- iOS/macOS（darwin）：`UriAudioSource.m:72` → `[AVURLAsset URLAssetWithURL:[NSURL URLWithString:uri] options:assetOptions]`，同样原样透传。

来源：`just_audio-0.10.6` / `0.10.5` 发布归档源码　置信度：**高**

### 5.2 强证据：真实 Subsonic/Jellyfin 类客户端就是这么做的

**Finamp**（Flutter 版 Jellyfin 音乐客户端，`just_audio ^0.9.42` + `audio_service ^0.18.15` + `audio_session ^0.1.21`），`lib/services/music_player_background_task.dart` 的 `_songUri()`：

```dart
Map<String, String> queryParameters = Map.from(parsedBaseUrl.queryParameters);

// We include the user token as a query parameter because just_audio used to
// have issues with headers in HLS, and this solution still works fine
queryParameters["ApiKey"] = _finampUserHelper.currentUser!.accessToken;
...
return Uri(
  host: parsedBaseUrl.host, port: parsedBaseUrl.port, scheme: parsedBaseUrl.scheme,
  userInfo: parsedBaseUrl.userInfo, pathSegments: builtPath,
  queryParameters: queryParameters,
);
```

即：**生产级客户端把认证 token 放 query string**，并明确注释说 headers 在 HLS 上「used to have issues」。这与 Hoomy 的 Subsonic `?u=..&t=..&s=..` 形态完全一致。
来源：<https://github.com/finamp-app/finamp>（本次 clone 源码）　置信度：**高**

### 5.3 `httpHeaders`：**支持**，但有代理/明文流量副作用

- API：`player.setUrl(url, headers: {...})` 与 `AudioSource.uri(uri, headers: ...)`；构造参数 `useProxyForRequestHeaders`（默认 `true`）。
- 平台支持表：request headers → Android ✅ / iOS ✅ / macOS ✅ / **Web ✗**（Web 只能用 Cookie）。
- 默认实现走**本地 HTTP 代理**：Android / iOS / macOS 上**都需要开启非 HTTPS 访问**（Android 加 `android:usesCleartextTraffic="true"` 或 `network_security_config` 允许 `127.0.0.1`；iOS 加 `NSAllowsArbitraryLoads`）。
- 设 `useProxyForRequestHeaders: false` 则走平台原生实现；但 **iOS 没有官方的 header API**，会退回到**未公开的** `AVURLAssetHTTPHeaderFieldsKey`（iOS 16+ 的 User-Agent 用官方 `AVURLAssetHTTPUserAgentKey`）。

来源：just_audio README「Working with headers」+ Platform support 表　置信度：**高**

**对 Hoomy 的含义**：既然走 query string 认证（ADR-0008 决策 3），就**不必碰 httpHeaders**，也就不必付出「本地代理 + 必须开明文流量」的代价。这是 just_audio 方案里最干净的一条路径。

### 5.4 seek / 流式播放的已知 issue

| Issue | 状态 | 与 Hoomy 的相关性 |
|---|---|---|
| **#440** | OPEN，2021-07-05 → 2024-10-13，22 条评论 | **FLAC seek 落点偏早 5–30 秒**。复现基于官方 example（macOS），但根因在 FLAC seek table 处理，非 macOS 特有。曲库 769/908 为 flac → **高相关** |
| **#685** | OPEN，2022-03-15 → 2024-11-27，36 条评论 | `[iOS][StreamAudioSource] PlayerException (-11850) Operation Stopped`。**仅影响 `StreamAudioSource` 路径**（自建字节流），普通 URL 串流不走这条路 → 低相关 |
| **#753 / #1084 / #1435 / #1599** | 均 OPEN | iOS seek / position / duration 异常系列（#1084：「iOS 播放中 seek 后无声、进度错误，pause/play 后恢复」）。普通 URL 播放场景下**中相关** |
| **#685 / headers** | — | 搜索 `repo:ryanheise/just_audio httpHeaders seek` 仅命中 1 条（即 #685），**没有**「带 header 的流上 seek 被忽略」这类 issue。ADR-0008 里 media_kit 的那类「带 httpHeaders 时 `Media(start:)`/`seek()` 被忽略」问题，**在 just_audio 上没有对应 issue** |

来源：GitHub Issues API 搜索与逐条读取　置信度：**中**

---

## 六、体积对比（iOS / Android）

**方法说明**：没有找到官方/权威的对比数字，以下全部为**本次自行测量**——直接下载 pub.dev 发布归档与 GitHub Release 产物并统计二进制大小。这比任何博客数字都硬，但它是「未压缩产物大小」，不等于最终 App 包增量（App Store 会剥离模拟器 slice 并压缩；Android 会用 R8 收缩、按 ABI 拆分）。

### 6.1 `media_kit`（audio-only，default 构建）

**Android**（`media_kit_libs_android_audio` **1.3.8** → 从 `libmpv-android-audio-build` **v1.1.8** 下载 per-ABI jar）：

| ABI | Release jar（下载体积） | 解包后 .so |
|---|---|---|
| `arm64-v8a` | 2,983,585 B（2.8 MiB） | `libmpv.so` 6,215,848 B + `libmediakitandroidhelper.so` 386,696 B = **6,602,544 B ≈ 6.3 MiB** |
| `armeabi-v7a` | 2,865,617 B（2.7 MiB） | 同量级 |
| `x86_64` | 3,114,935 B（3.0 MiB） | 同量级 |

**iOS**（`media_kit_libs_ios_audio` **1.1.4** → `libmpv-darwin-build` **v0.6.0** 的 `libmpv-xcframeworks_v0.6.0_ios-universal-audio-default.tar.gz`，tar.gz = 8,030,652 B）：

- **真机 slice `ios-arm64` 合计 6,529,848 B ≈ 6.2 MiB**（10 个 xcframework；其中 `Mpv` 1,846,704 B、`Avcodec` 1,431,968 B、`Avformat` ~1.3 MB、`Mbedcrypto` 974,224 B…）
- 模拟器 slice（`ios-arm64_x86_64-simulator`）合计 13,393,042 B ≈ 12.8 MiB —— **不上架包，App Store 会剥离**

来源：`https://pub.dev/api/archives/media_kit_libs_android_audio-1.3.8.tar.gz`（内含 `android/build.gradle` 的下载 URL 与 MD5）、`https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8`、`https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.6.0`　置信度：**高**（体积为实测）

### 6.2 `just_audio`

**Android**（Media3 **1.4.1**，Google Maven 实测 AAR 体积）：

| 模块 | AAR 字节 |
|---|---|
| `media3-exoplayer` | 1,440,873 |
| `media3-extractor` | 774,439 |
| `media3-common` | 479,222 |
| `media3-datasource` | 161,706 |
| `media3-container` | 24,985 |
| `media3-decoder` | 17,747 |
| **小计（核心）** | **2,898,972 ≈ 2.8 MiB** |
| `media3-exoplayer-hls`（just_audio 显式依赖） | 167,058 |
| `media3-exoplayer-dash` | 139,125 |
| `media3-exoplayer-smoothstreaming` | 51,015 |
| **总计** | **≈ 3,256,170 B ≈ 3.1 MiB** |

**与 ABI 无关**（纯 Java/Kotlin 字节码，一份 DEX 服务所有 ABI；R8 收缩后还会更小）。`just_audio` 自身 android 源码仅 80 KB。
来源：`https://dl.google.com/dl/android/maven2/androidx/media3/<module>/1.4.1/<module>-1.4.1.aar`（HTTP Content-Length 实测）、发布归档源码　置信度：**高**（体积为实测）

**iOS**：**没有任何第三方二进制依赖**。`just_audio` 的 darwin 实现为 24 个 Objective-C 源文件、共 156 KB（`AVPlayer` / `AVQueuePlayer` / `AVAudioSession`，全部调用系统框架）；`audio_service` 的 darwin 实现为 1 个 `.m` 文件、36 KB（`MediaPlayer` 框架的 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`）。编译进 App 后是极小的 ObjC 增量，**不引入任何 .framework**。
来源：发布归档 `just_audio-0.10.6` / `audio_service-0.18.19` 的 darwin 目录实测（`du -sh` + grep 框架引用）　置信度：**高**（目录与源码规模为实测）

### 6.3 增量差异结论

| 平台 | `just_audio` 侧 | `media_kit` 侧 | 差值 |
|---|---|---|---|
| **iOS（真机 arm64）** | ≈ 0（无第三方二进制，仅 ~190 KB ObjC 源码编译产物） | **≈ 6.2 MiB**（10 个 xcframework 的 device slice） | **media_kit 多约 6.2 MB** |
| **Android（单 ABI，如 arm64-v8a）** | ≈ 3.1 MiB（ABI 无关，一次性） | **≈ 6.3 MiB**（每 ABI 一份） | media_kit 多约 3.2 MB/ABI |
| **Android（含 arm64 + armeabi-v7a 的通用包）** | ≈ 3.1 MiB | ≈ 12.6 MiB | media_kit 多约 9.5 MB |

注意：`media_kit` 的库体积取决于所选构建变体——`audio-default`（本次统计的变体）最小；`audio-encodersgpl` / `audio-full` 在 iOS 真机 slice 上分别对应 7.9 MiB / 5.6 MiB 的 tar.gz（未解包统计），video 变体更大。**用错变体会显著放大体积**。

---

## 七、社区实践量级（补充事实）

### 7.1 开源 Flutter 音乐客户端的音频库选择（本次逐个 clone/fetch pubspec 核实）

| 项目 | 类型 | 星标 | 音频栈 |
|---|---|---|---|
| **finamp-app/finamp** | Jellyfin 音乐客户端 | — | `just_audio ^0.9.42` + `audio_service ^0.18.15` + `audio_session ^0.1.21` |
| **austinried/subtracks** | Subsonic 客户端 | — | `just_audio ^0.9.31` + `audio_service`（fork） |
| **dddevid/Musly** | Subsonic 客户端 | 545 | `just_audio ^0.9.46` + `audio_service ^0.18.18` + `audio_session`；Linux/macOS 后端换 `just_audio_media_kit` |
| **esiqveland/subsound** | Subsonic 客户端 | 33 | `just_audio ^0.9.0` + `audio_service ^0.18.0` + `just_audio_mpv` |
| **wellmoonloft/xiumusic** | Navidrome 客户端 | 25 | `just_audio ^0.9.41` + `just_audio_background ^0.0.1-beta.13` |
| **ulysg/k19-player** | OpenSubsonic 客户端 | 15 | `just_audio ^0.9.36` + `just_audio_background ^0.0.1-beta.11` |
| **JulyWitch/Dururu** | Subsonic 客户端 | 15 | `just_audio ^0.9.42` + `just_audio_background ^0.0.1-beta.14` |
| **SuperFola/FlSub** | Subsonic & Ampache | 7 | `just_audio ^0.9.34` + `just_audio_background ^0.0.1-beta.10` |
| **patroclos/sonicear** | Subsonic 客户端 | 9 | `just_audio ^0.5.5` + `audio_service ^0.15.2` |
| **DwifteJB/cosmodrome** | Subsonic (Navidrome) | 2 | `just_audio ^0.9.41` + `just_audio_background ^0.0.1-beta.17` + `just_audio_media_kit` |
| **HaZoru/pipe** | Subsonic 客户端 | 5 | `just_audio ^0.9.32` + `just_audio_background ^0.0.1-beta.9` |
| **AfalpHy/sylvakru** | 自建曲库播放器 | 558 | **`media_kit` + `media_kit_libs_*` + `audio_service ^0.18.18` + `audio_session ^0.2.2`**（唯一非 just_audio 者） |

**结果：12 个抽样项目中 11 个用 `just_audio`，1 个（sylvakru）用 `media_kit`。** 多个项目（Musly、cosmodrome）的做法正是 ADR-0008 记录的思路——**移动端 just_audio 原生 + 桌面端用 `just_audio_media_kit` 换成 libmpv 后端**。
来源：各仓库 `pubspec.yaml` / `git clone` 实测　置信度：**高**

### 7.2 下载量量级

`just_audio` 1,095,728 / 30 天；`audioplayers` 1,228,406；`media_kit` 334,407；`audio_service` 204,802。
来源：pub.dev `score` API　置信度：**高**

### 7.3 关于 `just_audio_media_kit`（第 1 组问题 4 的答案）

- 存在，最新 **2.1.0**（2025-04-13），19 likes，纯 Dart 包（归档内**无** android/ios/macos 原生目录）。
- 作用：用 `media_kit`（libmpv/FFmpeg）**替换 just_audio 的解码后端**——实现 `just_audio_platform_interface`，因此 just_audio 的 API 完全不变。
- 官方定位：README 标题即「package:media_kit bindings for just_audio to **support Linux and Windows**」；`JustAudioMediaKit.ensureInitialized()` 默认只开 `linux: true, windows: true`，**Android / iOS / macOS 默认关闭**，需显式传参并为每个平台额外引入 `media_kit_libs_*`。README 原文：「However, this is not required as they're **natively supported by just_audio**」。
- 维护状态：2025-04-13 后无新版本；最近一次改动是适配 `just_audio_platform_interface 4.5.0`（由 ryanheise 提交 PR #23）。19 likes 说明用户量小。
- **对本项目的意义**：既然 Windows/macOS 已砍，`just_audio_media_kit` **没有用武之地**；它的存在只证明了「just_audio 有可替换后端机制」这一事实，而不构成在 iOS/Android TV 上使用 media_kit 后端的理由（真这么做等于把 media_kit 的全部格式能力搬回来，也把 6 MB 体积和「内核无会话语义」一起搬回来）。

来源：<https://pub.dev/api/packages/just_audio_media_kit>、<https://github.com/Pato05/just_audio_media_kit>　置信度：**高**

---

## 事实小结（只列事实，不含建议）

### 支持「换 just_audio」的最强事实依据

1. **社区主流是压倒性的**：抽样的 12 个 Flutter Subsonic / Navidrome / Jellyfin 客户端里，**11 个用 `just_audio`**（Finamp、subtracks、Musly、subsound、xiumusic、k19-player、Dururu、FlSub、sonicear、cosmodrome、pipe），只有 sylvakru 用 media_kit；`just_audio` 是 pub.dev Flutter Favorite，30 天下载 1,095,728 次（media_kit 334,407）。
2. **官方推荐关系是双向的、白纸黑字的**：`audio_service` README 直接以「music player app might implement these callbacks using just_audio」为例；`just_audio` README 把 `audio_service` 列为进阶后台方案。`just_audio_background` 本身也依赖 `audio_service`。
3. **media_kit 在 iOS 后台这件事上是结构性缺口，且有官方承认的失败记录**：`media_kit` 1.2.6 的 `lib/` 中 `AVAudioSession` / `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` / `MediaSession` / `audio_service` / `audio_session` **命中 0 次**（本次独立 grep）；`media_kit_os_controls` 在 pub.dev **404**；`media-kit#1227`「Background audio playback (audio_service) on iOS not working」closed as completed，全程**仅 1 条评论且非维护者修复**。而 `audio_service` 的 darwin 实现直连 `MediaPlayer` 框架并管理 `AVAudioSession`。
4. **体积上 just_audio 在 iOS 是零第三方二进制**：iOS 真机 slice 增量 ≈ 0（仅 156 KB ObjC 源码 + 系统 AVFoundation），media_kit 是 6.2 MiB 的 10 个 xcframework。Android 侧媒体库体积 media_kit（6.3 MiB/ABI）也大于 just_audio（3.1 MiB，ABI 无关）。
5. **query string 认证正是 just_audio 生态里的成熟做法**：Finamp 把 Jellyfin token 放进 query（源码注释：「just_audio used to have issues with headers in HLS, and this solution still works fine」），与 Hoomy 的 Subsonic `?u=..&t=..&s=..` 完全同形。走 query string 还可以完全绕开 `httpHeaders` 带来的「本地代理 + 必须开明文流量」副作用。
6. **Android 后台是文档化的完整路径**：audio_service 给出了 MediaSession + MediaStyle 通知 + `mediaPlayback` 前台服务的完整 Manifest；Android 15 的 6 小时超时只针对 `mediaProcessing`/`dataSync`，不针对 `mediaPlayback`；`mediaSession.setActive(true)` 已实现，而 Android TV 的 Now Playing 卡片正是由 active MediaSession 驱动。
7. **iOS 的问题是「有修复、未发版」，不是「结构坏了」**：`#1139` 的根因是 darwin 里一处 `#if TARGET_OS_OSX` 守卫导致的播放状态不上报，PR #1140 已于 2026-07-01 合并进 `minor`，2026-07-06 在真机 iPad / iPadOS 26.5.2 上被确认修好；只是 0.18.20 截至 2026-09-10 未发布到 pub.dev，可用 `dependency_overrides` 立即拿到。

### 支持「留 media_kit」的最强事实依据

1. **Android 上的 FLAC 是 just_audio 的真实短板，而 flac 是曲库主力（769/908）**：just_audio 用 Media3 core 的 FLAC extractor（`DefaultExtractorsFactory`，源码 `AudioPlayer.java:613-614`），**不带** `media3-decoder-flac` 扩展；Media3 官方明文——该路径依赖 `MediaCodec` FLAC 解码器，**required from API level 27**。Android TV 7.1(API 25) / 8.0(API 26) 低于此线。media_kit 走 FFmpeg，格式覆盖与 hi-res 不受设备解码器限制。
2. **Android 平台 FLAC 解码器本身有硬性能力上限**：官方格式表写明「**Mono/Stereo (no multichannel). Sample rates up to 48 kHz**（44.1 kHz 更推荐）… **16-bit recommended**; no dither applied for 24-bit」。即 hi-res FLAC 在 MediaCodec 路径上不可靠。
3. **just_audio 有真实的 Android FLAC 故障 issue，且未内置兜底**：`#1017`（OPEN，Android 5 上 FLAC 有声轨数据但**完全没声音**）；`#814`/`#868`（部分 FLAC 报 `MediaCodecAudioRenderer: Audio codec error`，报告者实测**升级 ExoPlayer 无效**，最终靠自己引入 ExoPlayer 的 FLAC extension/libflac 才解决；just_audio 至今未内置该扩展）。
4. **FLAC seek 落点偏早的 bug 存在 4 年、22 条评论仍未修**：`#440`（OPEN，2021-07-05 → 2024-10-13），>3 分钟的 FLAC seek 偏早 5–30 秒。
5. **已发布的 audio_service（0.18.19）在 iOS 上不上报播放状态**：`#1139` 影响 0.18.18/0.18.19，症状包括锁屏/控制中心无控件、Dynamic Island 不显示、CarPlay 不工作、其他 App 播放不打断本 App。对「换 just_audio 后锁屏控制即可用」这一预期构成直接反例——**不改 pubspec 指 git 就用不了**。
6. **just_audio 在 Android TV 上有未修的生产事故 issue**：`#1179`（OPEN，Crashlytics 上报的 `MissingPluginException: No implementation found for method dispose`，**mainly on Android TV devices**，维护者明确表示无法调查、无修复）。
7. **`httpHeaders` 路径的副作用**：默认经本地 HTTP 代理实现，Android/iOS 都必须开启非 HTTPS/明文流量（或为 `127.0.0.1` 单独放行）；iOS 关掉代理后走的是**未公开 API** `AVURLAssetHTTPHeaderFieldsKey`。
8. **`audio_service` 自身也有 Android 后台稳定性 issue**：`#1165`（OPEN，2026-07-26）`AudioService.onCreate()` 中 `getFlutterEngine()` 阻塞主线程导致后台服务启动 ANR；`#932`（三星）、`#996`（`ForegroundServiceStartNotAllowedException`）、`#1062`（A14 通知播放键）均 OPEN。

### 明确「未能核实」的项

- **just_audio 官方格式支持表不存在**。其 README 只给了一个 StackOverflow 链接（<https://stackoverflow.com/questions/73557707>），该页被 Cloudflare 拦截，本次未能读取。所有格式结论均来自 Media3 / Android 官方文档与 just_audio 源码。
- **没有官方或权威的 just_audio vs media_kit 体积对比数字**。本报告第六节的全部数字为本次实测（见方法说明），非引用。
- **没有找到 Android TV 上使用 just_audio / audio_service 的开源 Flutter 音乐 App 先例**。找到的 Flutter Android TV 项目（ZY-Player-TV 199★、tubi_tv_flutter 145★）均为视频类，且 ZY-Player-TV 最后提交于 2021-01。
- **D-pad 媒体键在具体 Android TV 机型上是否与手机 100% 一致，无第一手报告**。官方文档描述的是 MediaSession 的路由规则（系统自动分发），但这只是机制说明，不等于机型实测。
- **Android TV 版本 ↔ API level 的逐条映射**未在单一官方页面上找到（API 21+ 下限有官方明文；7.1=25、8.0=26、9=28 为公开常识）。
- **ADR-0008 中「iOS 锁屏后音频停止（OPEN 两年余未修）」的精确对应 issue 未找到**。最接近的是 `#993`「iOS 16 后台加载新曲目时卡死」（2023-01-24 开，至今 OPEN）。

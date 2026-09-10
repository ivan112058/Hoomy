# 0002 - 播放内核统一使用 media_kit

日期：2026-09-08　状态：已接受

## 背景

Hoomy 需在 iOS、Android TV、macOS、Windows 四平台播放 flac/mp3/m4a 流。候选：media_kit（统一后端）、just_audio（移动端成熟、桌面靠桥接包）、各平台原生实现多套。

## 决策

全平台统一使用 media_kit。

## 后果

- 一套播放逻辑、格式能力一致（底层 FFmpeg），无需为桌面端维护第二套音频栈。
- 代价：iOS 上 media_kit 生态不如 just_audio 成熟，锁屏/后台控制需自行接 audio_session 与系统集成；体积因 FFmpeg 增大。
- 替换成本高，若 iOS 端暴露难以接受的缺陷，回退方案是 iOS 单独走 just_audio。

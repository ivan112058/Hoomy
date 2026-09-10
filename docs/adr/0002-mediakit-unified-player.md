# 0002 - 播放内核统一使用 media_kit

日期：2026-09-08　状态：已接受（**正在重新评估**：2026-09-10 决定砍掉 Windows，并重新审视「统一内核 vs 各平台最优实现」，结论将以新 ADR 记录）

## 背景

Hoomy 需在 iOS、Android TV、macOS 播放 flac/mp3/m4a 流（原含 Windows，已于 2026-09-10 砍掉）。候选：media_kit（统一后端）、just_audio（移动端成熟、桌面靠桥接包）、各平台原生实现多套。

## 决策

全平台统一使用 media_kit。

## 后果

- 一套播放逻辑、格式能力一致（底层 FFmpeg），无需为桌面端维护第二套音频栈。
- **`media_kit` 不含后台播放与系统媒体控制**，该职责另由 `audio_service` + `audio_session` 承担，见 ADR-0008。这是本决策的必然配套，不是可选优化。
- 代价：iOS 上 media_kit 生态不如 just_audio 成熟，媒体会话层的 iOS 实现存在未修 issue（详见 ADR-0008），必须在真机验收；体积因 FFmpeg 增大。
- 替换成本高，若 iOS 端暴露难以接受的缺陷，回退方案是 iOS 单独走 just_audio。

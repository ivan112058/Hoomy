# 0011 - 采用 pub.dev 发布版依赖，iOS 锁屏与 Android FLAC 暂不深究

日期：2026-09-10　状态：已接受

## 背景

更换播放内核（ADR-0010）后浮现两个已知缺陷，需要决定是否在 MVP 阶段处理：

1. **iOS 锁屏/控制中心在已发布版本上不工作**：`audio_service` issue #1139，影响已发布的 0.18.18 / 0.18.19（iOS ≥ 13 收不到播放状态，导致锁屏无控件、Dynamic Island 不显示、CarPlay 不工作、不打断其他 App）。修复（PR #1140）已合并进 git `minor` 分支并有真机验证，但 0.18.20 尚未发布到 pub.dev。
2. **Android FLAC 的兼容边界**：`just_audio` 走 Media3 core extractor，依赖设备 MediaCodec FLAC 解码器（Media3 要求 API ≥ 27），且有未修 issue（#440 seek 偏早、#868 解码错误）。曲库 908 首中 769 首为 flac。

## 决策

1. **依赖一律使用 pub.dev 的发布版本**，不引入 `dependency_overrides`，不锁 git ref。理由是保持依赖可复现、可审计；锁到未发布分支会把「上游何时发版」变成项目的隐性依赖。
2. **本阶段不深入 iOS 锁屏控制与 Android FLAC 两个问题**。它们不作为 MVP 的验收项，也不为它们增加设计复杂度。
3. **保留两条已知回退路径**，不预先实现：
   - iOS 锁屏：若验收时确认为阻塞，`dependency_overrides` 指向 `audio_service` 的 git `minor` 分支（固定 commit）。
   - Android FLAC：若真机证伪，在 Android 侧挂 `just_audio_media_kit`（换用 libmpv 解码后端），`just_audio` 的 Dart API 不变，Dart 侧代码无需改动。
4. **目标设备事实已确认，风险已降级**：验收电视为 Sony KD-55X9500G（BRAVIA 4K UR2），**Android TV 10 = API 29**，在 Media3 要求的 API 27 之上。因此「旧 Android TV 无法解码 flac」这一风险在本项目不成立。

## 后果

- **iOS 的锁屏/控制中心在采用范围内很可能不可用**，这不是配置问题，且在改用 git 版本前无法修复。若「后台播放与锁屏控制」被当作 MVP 必含项来验收，此条会成为未达标项——这是一个**已知且已记录的缺口**，不是遗漏。
- Android FLAC 的风险被缩小到「#440 / #868 是否在本设备的曲目上复现」，而不再包含 API level 兼容性。
- 由于 `PlayerEngine` 接缝存在，两条回退路径都是替换实现而非架构变更，推迟处理的代价可控。
- 若后续决定处理，本 ADR 应被新的 ADR 取代，而不是就地改写。

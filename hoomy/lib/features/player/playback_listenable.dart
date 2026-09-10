import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/playback_controller.dart';
import '../../player/player_providers.dart';

/// 订阅播放状态的重绘边界。
///
/// 播放状态经 [PlaybackController] 的 [ChangeNotifier] 广播，而 provider 的值
/// （控制器对象本身）从不变化 —— 直接 `ref.watch(playerControllerProvider)`
/// 不会因播放状态变化而重绘。想让某个部件跟着播放状态更新，就把它包在这里：
/// 只有 [builder] 返回的这一层重绘。
///
/// 注意通知频率：进度每 ~200ms 推一次，所以 [builder] 里不要构建整页 ——
/// 列表这类「只关心当前曲目」的界面请用 [CurrentSongIdBuilder]，它只在那一个
/// id 变化时才重建。
///
/// 没有控制器（未登录）时不调用 [builder]。
class PlaybackListenable extends ConsumerWidget {
  const PlaybackListenable({super.key, required this.builder});

  /// 构建函数：拿到当前播放控制器。
  final Widget Function(BuildContext context, PlaybackController controller)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playerControllerProvider);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => builder(context, controller),
    );
  }
}

/// 只在**当前播放曲目 id** 变化时重建的边界。
///
/// 播放列表里「哪一行在播」只随当前曲目变，不该跟着进度每 ~200ms 重建整份
/// 列表。[builder] 拿到 null 表示没有当前曲目（含未登录）。
class CurrentSongIdBuilder extends ConsumerWidget {
  const CurrentSongIdBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, String? currentSongId) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playerControllerProvider);
    if (controller == null) return builder(context, null);
    return StreamBuilder<String?>(
      // `distinct()` 让相同 id 的重复通知不再触发重建；初值由 builder 先按
      // null 构建一帧，因此列表不会因为等待首帧而空着。
      stream: controller.currentSongIdStream,
      builder: (context, snapshot) => builder(context, snapshot.data),
    );
  }
}

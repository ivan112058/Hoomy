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
/// 通知频率：进度每 ~200ms 推一次。需要一个**只跟着部分状态**更新、不被进度
/// 拖着重绘的部件时，用 [select] 把关心的那部分挑出来：只有它变了才重建
/// （迷你播放条与错误提示条都这么用）。列表这类「只关心当前曲目」的界面
/// 请用 [CurrentSongIdBuilder]，它只在那一个 id 变化时才重建。
///
/// 没有控制器（未登录）时不调用 [builder]。
class PlaybackListenable extends ConsumerWidget {
  const PlaybackListenable({super.key, required this.builder, this.select});

  /// 构建函数：拿到当前播放控制器。
  final Widget Function(BuildContext context, PlaybackController controller)
  builder;

  /// 关心的那部分播放状态；挑出的值不变时不重建。
  ///
  /// 传 null（默认）表示任何变化都重建 —— 进度每 ~200ms 推一次，
  /// [builder] 里不要构建整页。
  final Object? Function(PlaybackController controller)? select;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playerControllerProvider);
    if (controller == null) return const SizedBox.shrink();
    final select = this.select;
    return _SelectedListenable(
      controller: controller,
      select: select,
      builder: (context) => builder(context, controller),
    );
  }
}

/// 按 [PlaybackListenable.select] 挑出的值去重的重建边界。
class _SelectedListenable extends StatefulWidget {
  const _SelectedListenable({
    required this.controller,
    required this.select,
    required this.builder,
  });

  final PlaybackController controller;
  final Object? Function(PlaybackController controller)? select;
  final WidgetBuilder builder;

  @override
  State<_SelectedListenable> createState() => _SelectedListenableState();
}

class _SelectedListenableState extends State<_SelectedListenable> {
  /// 上一次挑出的值；[Object.==] 判等，记录与列表比较也按值相等。
  Object? _selected;

  @override
  void initState() {
    super.initState();
    _selected = _read();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_SelectedListenable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      _selected = _read();
      widget.controller.addListener(_onChanged);
      return;
    }
    // select 换了一个函数对象也要重新取一次值，否则会拿旧口径去比较。
    if (oldWidget.select != widget.select) _selected = _read();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  Object? _read() => widget.select?.call(widget.controller);

  void _onChanged() {
    // 没有 select 就是「任何变化都重建」：不能拿 null 去判等，否则默认路径
    // 会永远认为「没变」而一次都不重建。
    if (widget.select == null) {
      setState(() {});
      return;
    }
    final next = _read();
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
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

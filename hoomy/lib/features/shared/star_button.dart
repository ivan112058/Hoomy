import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/star/star_store.dart';
import '../../data/star/star_target.dart';
import 'error_retry_view.dart';
import 'hoomy_list_row.dart';

/// 收藏星标：乐观更新 + 失败回滚 + 同目标互斥的**唯一**界面落点（票据 12）。
///
/// 点一下立刻按新状态上色，不等网络往返；写失败则回滚到 [starred] 并弹出
/// 可读提示。本地乐观值在 [starred] 变化（重新取数、别的入口改过）时清除，
/// 因此**以服务端状态为准**。
///
/// 颜色规则也收在这里，不让五个入口各抄一遍「已收藏→播放红」：
/// 默认口径是 [HoomyPalette.playing]／[HoomyPalette.textPrimary]，
/// 列表行用 [StarButton.inRow]，让星标跟随整行的按压反馈。
class StarButton extends ConsumerStatefulWidget {
  const StarButton({
    super.key,
    required this.target,
    required this.starred,
    this.iconSize,
    this.padding,
    this.constraints,
  }) : rowState = null;

  /// 列表行里的星标：未按下且已收藏时用播放红，按下时随整行变白。
  const StarButton.inRow({
    super.key,
    required this.target,
    required this.starred,
    required HoomyRowState state,
    this.iconSize,
    this.padding,
    this.constraints,
  }) : rowState = state;

  /// 收藏目标（歌曲/专辑/歌手 + 服务端 id）。
  final StarTarget target;

  /// 服务端状态：是否已收藏。
  final bool starred;

  /// 所在行的按压状态；非 null 时颜色改走行内口径。
  final HoomyRowState? rowState;

  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  @override
  ConsumerState<StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends ConsumerState<StarButton> {
  /// 本地乐观值；null 表示跟随服务端状态 [StarButton.starred]。
  bool? _optimistic;

  bool get _effective => _optimistic ?? widget.starred;

  @override
  void didUpdateWidget(StarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 目标换了或服务端状态变了：丢掉本地乐观值，重新以服务端为准。
    if (widget.target != oldWidget.target ||
        widget.starred != oldWidget.starred) {
      _optimistic = null;
    }
  }

  Future<void> _toggle() async {
    final store = ref.read(starStoreProvider);
    // 同目标已有请求在途：忽略这次点击，不做乐观更新也不发第二个请求。
    if (store.isSaving(widget.target)) return;
    final desired = !_effective;
    // 先取好 messenger：await 之后 context 可能已经失效。
    final messenger = ScaffoldMessenger.of(context);
    // 乐观更新：界面立刻反映新状态。
    setState(() => _optimistic = desired);
    try {
      await store.setStarred(target: widget.target, starred: desired);
    } catch (error) {
      // 失败回滚到服务端状态，并给出可读原因。
      if (mounted) setState(() => _optimistic = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${desired ? '收藏' : '取消收藏'}失败：${describeError(error)}',
          ),
        ),
      );
    }
  }

  /// 星标颜色：已收藏点亮播放红，否则用所在表面的前景色。
  Color _color(BuildContext context, bool starred) {
    final palette = HoomyPalette.of(context);
    final rowState = widget.rowState;
    if (rowState != null) {
      return starred && !rowState.pressed
          ? palette.playing
          : rowState.foreground;
    }
    return starred ? palette.playing : palette.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final starred = _effective;
    return IconButton(
      onPressed: _toggle,
      color: _color(context, starred),
      tooltip: starred ? '取消收藏' : '收藏',
      iconSize: widget.iconSize,
      padding: widget.padding,
      constraints: widget.constraints,
      icon: Icon(starred ? Icons.star : Icons.star_border),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';

/// 一行加上其下分隔线的占位高度。
///
/// 分组列表按固定行高算 A–Z 快捷栏的跳转偏移，分隔线必须计入，
/// 否则每组的实际高度会比计算值多出一条线。
final kHoomyListRowExtent =
    HoomyDimens.listRowHeight + HoomyDimens.dividerThickness;

/// 行尾的整宽分隔线。
///
/// 高度锁成 [HoomyDimens.dividerThickness]，不跟随主题里 `Divider` 的
/// `space`（默认 16dp）：分组列表按「行 + 线」算整组高度，放任 `space`
/// 会让实际高度超出计算值，A–Z 快捷栏就跳不准。
class HoomyRowDivider extends StatelessWidget {
  const HoomyRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: HoomyDimens.dividerThickness,
      child: Divider(height: HoomyDimens.dividerThickness),
    );
  }
}

/// 一行内容 + 其下整宽分隔线，总高恰为 [kHoomyListRowExtent]。
///
/// 分组列表按固定行高算 A–Z 快捷栏的跳转偏移；把「行 + 线」封在这里，
/// 页面就不必各自拼 Column，也不会漏算分隔线使跳转错位。
class HoomyDividedRow extends StatelessWidget {
  const HoomyDividedRow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [child, const HoomyRowDivider()],
    );
  }
}

/// 一行的按压状态。
///
/// [foreground] 已由 [HoomyListRow] 按是否按下解析好：未按下是次文字色，
/// 按下是白色。行尾部件直接用它上色就能自动跟随按压反馈。
@immutable
class HoomyRowState {
  const HoomyRowState({required this.pressed, required this.foreground});

  /// 当前是否处于按下态。
  final bool pressed;

  /// 当前前景色。
  final Color foreground;
}

/// 曲库列表的通用行：直角、60dp 高，标题 16sp、副标题 13sp。
///
/// 按下时整行铺交互蓝、文字与图标变白 —— 参考项目用位图 selector，
/// Flutter 无对应机制，这里做等效反馈（ADR-0003）。
///
/// [trailing] 拿到 [HoomyRowState]：不含颜色的图标继承行内 [IconTheme]
/// 自动变白，需要显式着色的部件（收藏星标、时长文字）用
/// [HoomyRowState.foreground]。
class HoomyListRow extends StatefulWidget {
  const HoomyListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  /// 标题。
  final String title;

  /// 副标题；为空则不占位。
  final String? subtitle;

  /// 行首部件（图标等）。
  final Widget? leading;

  /// 行尾部件。
  final Widget Function(HoomyRowState state)? trailing;

  /// 点击回调；为 null 时仍保留按压反馈。
  final VoidCallback? onTap;

  @override
  State<HoomyListRow> createState() => _HoomyListRowState();
}

class _HoomyListRowState extends State<HoomyListRow> {
  /// 与 Android pressed-state 时长一致：同帧完成的点击也至少可见一瞬。
  static const _minPressedDuration = Duration(milliseconds: 64);

  bool _pressed = false;
  Timer? _releaseTimer;

  void _handlePressStart() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (!_pressed) setState(() => _pressed = true);
  }

  void _handlePressEnd() {
    if (!_pressed) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_minPressedDuration, () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final titleColor = _pressed ? palette.pressedForeground : palette.textPrimary;
    final secondaryColor = _pressed ? palette.pressedForeground : palette.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 用 tap 回调而不是 Listener：列表滚动时拖拽手势胜出会触发
      // onTapCancel，行不会在整段滑动里一直保持蓝色。
      onTapDown: (_) => _handlePressStart(),
      onTapUp: (_) => _handlePressEnd(),
      onTapCancel: _handlePressEnd,
      onTap: widget.onTap,
      child: ColoredBox(
        color: _pressed ? palette.pressedBackground : Colors.transparent,
        child: SizedBox(
          height: HoomyDimens.listRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IconTheme.merge(
              data: IconThemeData(color: secondaryColor),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: HoomyDimens.listTitleFontSize,
                            color: titleColor,
                          ),
                        ),
                        if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: HoomyDimens.listSubtitleFontSize,
                                color: secondaryColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.trailing != null)
                    widget.trailing!(
                      HoomyRowState(pressed: _pressed, foreground: secondaryColor),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

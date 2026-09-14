import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import 'hoomy_focusable.dart';

/// 图标按钮：直角、固定点击区，聚焦与悬停复用按压反馈的视觉
/// （整块交互蓝 + 图标变白，ADR-0013 决策 2）。
///
/// 不用 Material 的 `IconButton`：它自建焦点节点，外层拿不到「已聚焦」这一
/// 事实，画不出整块蓝底；而全局改 `IconButtonTheme` 又会连带覆盖各处显式
/// 指定的图标色（收藏星标的播放红、迷你播放条的激活色）。把按钮做成一个
/// [HoomyFocusable]，颜色规则就只有这一处。
///
/// [active] 表达「开关处于开启态」（循环非关、随机打开、已收藏）：常态用播放红，
/// 与 `PlaybackControls` 原有口径一致；聚焦时仍统一变白。
class HoomyIconButton extends StatelessWidget {
  const HoomyIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconSize = 24,
    this.color,
    this.active = false,
    this.autofocus = false,
    this.size = 48,
  });

  final IconData icon;

  /// 为 null 时不可点、不进焦点序列，并显示禁用色。
  final VoidCallback? onPressed;

  /// 无障碍与长按提示；同时是测试里定位按钮的手段。
  final String? tooltip;

  final double iconSize;

  /// 常态颜色；null 用主文字色。
  final Color? color;

  /// 是否处于开启态：常态用播放红。
  final bool active;

  final bool autofocus;

  /// 点击区边长。
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final onPressed = this.onPressed;
    final normalColor = onPressed == null
        ? Theme.of(context).disabledColor
        : active
        ? palette.playing
        : color ?? palette.textPrimary;

    Widget button = HoomyFocusable(
      onTap: onPressed,
      autofocus: autofocus,
      builder: (context, highlight) => ColoredBox(
        color: highlight.background(palette),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: highlight.foreground(palette, normalColor),
            ),
          ),
        ),
      ),
    );
    // 保住 Material 按钮的无障碍语义：`IconButton` 会声明 button 角色，
    // 换成自绘部件后要显式补回（涟漪本来就已由全局 NoSplash 关掉）。
    button = Semantics(button: true, enabled: onPressed != null, child: button);
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}

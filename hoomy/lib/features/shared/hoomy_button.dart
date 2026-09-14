import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import 'hoomy_focusable.dart';

/// 文本按钮：直角、有最小高度；聚焦复用按压反馈的视觉（ADR-0013 决策 2）。
///
/// 与 [HoomyIconButton] 同一口径，补的是 Material 那套文字按钮
/// （`FilledButton` / `OutlinedButton` / `TextButton`）在 TV 上的缺口：它们的
/// 聚焦反馈只是默认的半透明叠加，10-foot 距离下看不清；而登录按钮是 TV 上
/// 进入应用的第一步，聚焦必须看得见。
///
/// 视觉仍只用既有 token：填充态常态是播放红底 + 白字，文字态常态是播放红文字，
/// 高亮（按下 / 聚焦）统一铺交互蓝 + 白字。停用态沿用主题的禁用色。
class HoomyButton extends StatelessWidget {
  const HoomyButton({
    super.key,
    required this.child,
    this.onPressed,
    this.filled = false,
    this.bordered = false,
    this.minHeight = 44,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;

  /// 为 null 时不可点、不进焦点序列，用禁用色。
  final VoidCallback? onPressed;

  /// 填充态（对应 `FilledButton`）：常态铺播放红底 + 白字。
  final bool filled;

  /// 描边（对应 `OutlinedButton`）：边框跟随当前前景色，高亮时一起变白。
  final bool bordered;

  final double minHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final disabled = onPressed == null;
    final disabledColor = Theme.of(context).disabledColor;
    final normalForeground = disabled
        ? disabledColor
        : filled
        ? palette.pressedForeground
        : palette.playing;
    final normalBackground = filled
        ? (disabled ? disabledColor.withValues(alpha: 0.12) : palette.playing)
        : Colors.transparent;

    return Semantics(
      button: true,
      enabled: !disabled,
      child: HoomyFocusable(
        onTap: onPressed,
        builder: (context, highlight) {
          final foreground = highlight.foreground(palette, normalForeground);
          return ColoredBox(
            color: highlight.background(palette, normalBackground),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: bordered ? Border.all(color: foreground) : null,
                ),
                child: Padding(
                  padding: padding,
                  child: Center(
                    child: DefaultTextStyle.merge(
                      style:
                          (Theme.of(context).textTheme.labelLarge ??
                                  const TextStyle())
                              .copyWith(color: foreground),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

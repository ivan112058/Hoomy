import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import 'hoomy_focusable.dart';

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
    return Column(children: [child, const HoomyRowDivider()]);
  }
}

/// 一行的高亮状态。
///
/// [foreground] 已由 [HoomyListRow] 按是否高亮解析好：未高亮是次文字色，
/// 高亮（按下 / 聚焦 / 悬停）是白色。行尾部件直接用它上色就能自动跟随
/// 反馈，不必各自判断输入形态。
@immutable
class HoomyRowState {
  const HoomyRowState({required this.active, required this.foreground});

  /// 当前是否处于高亮态：按下、聚焦或悬停任一成立（ADR-0013 决策 2）。
  final bool active;

  /// 当前前景色。
  final Color foreground;
}

/// 曲库列表的通用行：直角、60dp 高，标题 16sp、副标题 13sp。
///
/// 按下时整行铺交互蓝、文字与图标变白 —— 参考项目用位图 selector，
/// Flutter 无对应机制，这里做等效反馈（ADR-0003）。TV 上聚焦与悬停走同一套
/// 视觉（ADR-0013）：焦点落在行上时也是整行蓝底、前景变白，不新增 TV 专属配色。
///
/// [trailing] 拿到 [HoomyRowState]：不含颜色的图标继承行内 [IconTheme]
/// 自动变白，需要显式着色的部件（收藏星标、时长文字）用
/// [HoomyRowState.foreground]。[leadingBuilder] 同理 —— 行首需要按状态着色
/// （例如播放标识按下时变白）时用它，而不是绕过这套反馈自己上色。
class HoomyListRow extends StatelessWidget {
  const HoomyListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingBuilder,
    this.trailing,
    this.onTap,
    this.onMovePrevious,
    this.onMoveNext,
    this.highlighted = false,
  });

  /// 标题。
  final String title;

  /// 副标题；为空则不占位。
  final String? subtitle;

  /// 行首部件（图标等），不随按压状态着色。
  final Widget? leading;

  /// 行首部件，拿到 [HoomyRowState] 自行着色（与 [trailing] 同口径）。
  final Widget Function(HoomyRowState state)? leadingBuilder;

  /// 行尾部件。
  final Widget Function(HoomyRowState state)? trailing;

  /// 点击 / 确认键回调；为 null 时仍保留按压反馈，但不进焦点序列。
  final VoidCallback? onTap;

  /// 左键回调：焦点停在行上时左键改判为上移（队列重排的 D-pad 路径）。
  final VoidCallback? onMovePrevious;

  /// 右键回调：与 [onMovePrevious] 对称，改判为下移。
  final VoidCallback? onMoveNext;

  /// 是否是当前播放的曲目：标题用播放态红标出。
  ///
  /// 高亮时仍按反馈统一变白，红色只在高亮的常态下可见。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return HoomyFocusable(
      onTap: onTap,
      onMovePrevious: onMovePrevious,
      onMoveNext: onMoveNext,
      builder: (context, highlight) {
        final titleColor = highlight.foreground(
          palette,
          highlighted ? palette.playing : palette.textPrimary,
        );
        final secondaryColor = highlight.foreground(
          palette,
          palette.textSecondary,
        );
        final rowState = HoomyRowState(
          active: highlight.highlighted,
          foreground: secondaryColor,
        );

        return ColoredBox(
          color: highlight.background(palette),
          child: SizedBox(
            height: HoomyDimens.listRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IconTheme.merge(
                data: IconThemeData(color: secondaryColor),
                child: Row(
                  children: [
                    if (leadingBuilder != null) ...[
                      leadingBuilder!(rowState),
                      const SizedBox(width: 16),
                    ] else if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: HoomyDimens.listTitleFontSize,
                              color: titleColor,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
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
                    if (trailing != null) trailing!(rowState),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

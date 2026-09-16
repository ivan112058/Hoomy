import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../player/mini_player_bar.dart';
import '../player/playback_error_banner.dart';
import '../shared/hoomy_focusable.dart';
import 'hoomy_destinations.dart';
import 'session_guard.dart';
import 'shell_actions.dart';

/// 侧边导航栏宽度：纵向图标 + 文字，10-foot 距离下读得清。
const kTvNavigationRailWidth = 132.0;

/// 侧边导航栏单项高度。
const _navItemHeight = 76.0;

/// Android TV 的主壳（ADR-0013 决策 1）。
///
/// 左侧为纵向图标 + 文字的一级导航（5 项），右侧为内容区；迷你播放条固定在
/// 内容区底部。与手机外壳的差别**只在 chrome**：页面、数据层与播放状态机完全
/// 共用（[kHoomyDestinations]）。
///
/// 为什么不是底部 Tab：迷你播放条已在底栏之上，两条横向 chrome 会在底边堆叠，
/// D-pad 要频繁在两者间穿梭；侧边导航栏与迷你条分处纵横两条 chrome，且
/// 左右键天然对应「导航 ↔ 内容」。
class TvHomeShell extends ConsumerStatefulWidget {
  const TvHomeShell({super.key});

  @override
  ConsumerState<TvHomeShell> createState() => _TvHomeShellState();
}

class _TvHomeShellState extends ConsumerState<TvHomeShell> {
  /// 默认停在「歌曲」——曲库的主要入口（与手机外壳一致）。
  int _index = 3;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Scaffold(
      body: Row(
        // 铺满高度：导航栏要能自己滚动（软键盘弹出时窗口变矮），内容区靠
        // Expanded 吃剩余宽度。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TvNavigationRail(
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
          Container(
            width: HoomyDimens.dividerThickness,
            color: palette.divider,
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SessionGuard(
                    child: IndexedStack(
                      index: _index,
                      children: [
                        for (final destination in kHoomyDestinations)
                          destination.page,
                      ],
                    ),
                  ),
                ),
                // 迷你播放条与错误提示固定在内容区底部：任何页面都能看到正在
                // 放什么、播放失败也能立刻看到原因。
                const PlaybackErrorBanner(),
                MiniPlayerBar(
                  onTap: () => openPlaybackFromShell(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一级导航栏：纵向 5 项，每一项都可聚焦（D-pad 上下移动，确认键切换）。
///
/// 可滚动：软键盘弹出时（`adjustResize`）窗口高度只剩几百 dp，5 × 76dp 的
/// 固定列会溢出；TV 上搜索/登录都要唤出键盘，这条路径真实存在。正常高度下
/// 内容装得下，不会出现滚动条。
class _TvNavigationRail extends StatelessWidget {
  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return SizedBox(
      width: kTvNavigationRailWidth,
      child: ColoredBox(
        color: palette.titleBar,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < kHoomyDestinations.length; i++)
                _TvNavItem(
                  destination: kHoomyDestinations[i],
                  selected: i == selectedIndex,
                  // 启动即聚焦当前项：遥控器一上来就有焦点可移动，不必先按一下
                  // 方向键。之后切换 Tab 时 autofocus 不会再次生效（只认首次挂载）。
                  autofocus: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 导航栏里的一项：图标 + 文字，聚焦时整块铺交互蓝、文字与图标变白
/// （与列表行同一套反馈，ADR-0013 决策 2）。
class _TvNavItem extends StatelessWidget {
  const _TvNavItem({
    required this.destination,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final HoomyDestination destination;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return HoomyFocusable(
      onTap: onTap,
      autofocus: autofocus,
      builder: (context, highlight) {
        final color = highlight.foreground(
          palette,
          selected ? palette.playing : palette.textSecondary,
        );
        return ColoredBox(
          color: highlight.background(
            palette,
            selected ? palette.surfaceRaised : Colors.transparent,
          ),
          child: SizedBox(
            width: kTvNavigationRailWidth,
            height: _navItemHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 26,
                  color: color,
                ),
                const SizedBox(height: 6),
                Text(
                  destination.label,
                  style: TextStyle(
                    fontSize: HoomyDimens.listSubtitleFontSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

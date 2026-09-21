import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../player/mini_player_bar.dart';
import '../player/playback_error_banner.dart';
import '../settings/settings_page.dart';
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
/// 左侧为纵向图标 + 文字的一级导航，右侧为内容区；迷你播放条固定在
/// 内容区底部。与手机外壳的差别**只在 chrome 与导航清单**：页面、数据层与播放
/// 状态机完全共用（`hoomy_destinations.dart`）。
///
/// 导航清单里没有「更多」：风格与我喜欢的歌曲直接是一级项，设置钉在导航栏
/// 最下面（票据 03 真机验收后按使用反馈调整）。
///
/// **聚焦即切换**：导航项拿到焦点就把内容切过去，不必再按确认键；确认键因此
/// 改为把焦点送进内容区。六个页面本就都挂在 `IndexedStack` 里，切换不产生取数。
/// 「设置」不是页面，不参与预览。上下键在首尾循环（首项 ↔ 设置）。
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
  int _index = kSongsDestinationIndex;

  /// 导航项**拿到焦点**即切换内容（A 口径：聚焦即切换）。
  ///
  /// 与手机外壳的差别：底部 Tab 要按一下，TV 上焦点扫过就展示 —— 少一次按键，
  /// 而且六个页面本来就都挂在 `IndexedStack` 里，切换不产生任何取数。
  void _onRailFocused(int i) {
    if (_index != i) setState(() => _index = i);
  }

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
            onFocused: _onRailFocused,
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
                        for (final destination in kTvDestinations)
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

/// 一级导航栏：纵向图标列，每一项都可聚焦；焦点一动，右侧内容就跟着切
///（「聚焦即切换」，见 [TvHomeShell]）。
///
/// 上下键在**首尾循环**：在「播放列表」按上键到「设置」，在「设置」按下键回到
/// 「播放列表」—— 电视遥控器没有指针，走到头再回顶比「卡住」更顺手。
///
/// 导航项可滚动：软键盘弹出时（`adjustResize`）窗口高度只剩几百 dp，固定列会
/// 溢出；TV 上搜索/登录都要唤出键盘，这条路径真实存在。设置项钉在最下面，
/// 不随导航项滚动 —— 它是唯一一个「不是页面」的入口。
class _TvNavigationRail extends StatefulWidget {
  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onFocused,
  });

  final int selectedIndex;

  /// 某项拿到焦点：切换右侧内容。
  final ValueChanged<int> onFocused;

  @override
  State<_TvNavigationRail> createState() => _TvNavigationRailState();
}

class _TvNavigationRailState extends State<_TvNavigationRail> {
  /// 首项与设置项由本部件持有：循环的两端要能互相指名交焦点。
  final _firstNode = FocusNode(debugLabel: 'TvNavFirst');
  final _settingsNode = FocusNode(debugLabel: 'TvNavSettings');

  @override
  void dispose() {
    _firstNode.dispose();
    _settingsNode.dispose();
    super.dispose();
  }

  /// 聚焦即切换之后，确认键不再是「切 Tab」（焦点已经把内容切过去了）；
  /// 让它把焦点送进内容区，键盘用户与方向键用户就都有同一条前进路径。
  void _enterContent() =>
      FocusManager.instance.primaryFocus?.focusInDirection(
        TraversalDirection.right,
      );

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final destinations = kTvDestinations;
    return SizedBox(
      width: kTvNavigationRailWidth,
      child: ColoredBox(
        color: palette.titleBar,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      _TvNavItem(
                        icon: destinations[i].icon,
                        selectedIcon: destinations[i].selectedIcon,
                        label: destinations[i].label,
                        selected: i == widget.selectedIndex,
                        // 启动即聚焦当前项：遥控器一上来就有焦点可移动，不必先按
                        // 一下方向键。之后切换 Tab 时 autofocus 不会再次生效
                        //（只认首次挂载）。
                        autofocus: i == widget.selectedIndex,
                        focusNode: i == 0 ? _firstNode : null,
                        onMoveUp: i == 0
                            ? () => _settingsNode.requestFocus()
                            : null,
                        // 聚焦即切换：拿到焦点就把右侧切过去。
                        onFocusChange: (hasFocus) {
                          if (hasFocus) widget.onFocused(i);
                        },
                        onTap: _enterContent,
                      ),
                  ],
                ),
              ),
            ),
            // 设置不是一级页面（推入的是层级路由），因此不参与 IndexedStack，
            // 也固定在最下面：它属于「本机设置」，不属于曲库浏览。
            _TvNavItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
              selected: false,
              autofocus: false,
              focusNode: _settingsNode,
              onMoveDown: () => _firstNode.requestFocus(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 导航栏里的一项：图标 + 文字，聚焦时整块铺交互蓝、文字与图标变白
///（与列表行同一套反馈，ADR-0013 决策 2）。
class _TvNavItem extends StatelessWidget {
  const _TvNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onTap,
    this.onFocusChange,
    this.focusNode,
    this.onMoveUp,
    this.onMoveDown,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  /// 焦点变化回调（聚焦即切换用）。
  final ValueChanged<bool>? onFocusChange;

  /// 外部节点：循环的两端由导航栏持有。
  final FocusNode? focusNode;

  /// 上键改判（首项 → 设置）。
  final VoidCallback? onMoveUp;

  /// 下键改判（设置 → 首项）。
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return HoomyFocusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
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
                Icon(selected ? selectedIcon : icon, size: 26, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

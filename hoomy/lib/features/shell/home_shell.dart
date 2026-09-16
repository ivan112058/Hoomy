import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/mini_player_bar.dart';
import '../player/playback_error_banner.dart';
import 'hoomy_destinations.dart';
import 'session_guard.dart';
import 'shell_actions.dart';

/// 手机外壳（iOS）：底部五 Tab——播放列表、艺术家、专辑、歌曲、更多。
///
/// TV 另有 [TvHomeShell]（侧边导航栏，ADR-0013 决策 1）；两者共用
/// [kHoomyDestinations] 里的页面清单，只有导航 chrome 不同。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SessionGuard(
        child: IndexedStack(
          index: _index,
          children: [
            for (final destination in kHoomyDestinations) destination.page,
          ],
        ),
      ),
      // 迷你播放条与错误提示挂在导航栏之上：任何 Tab 都能看到正在放什么、
      // 播放失败也能立刻看到原因，不会随页面切走而消失。
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlaybackErrorBanner(),
            MiniPlayerBar(
              // 点条身展开全屏播放页（覆盖层）；播放页里再展开队列覆盖层。
              onTap: () => openPlaybackFromShell(context, ref),
            ),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final destination in kHoomyDestinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

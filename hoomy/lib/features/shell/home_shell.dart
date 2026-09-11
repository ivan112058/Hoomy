import 'package:flutter/material.dart';

import '../albums/albums_page.dart';
import '../artists/artists_page.dart';
import '../more/more_page.dart';
import '../player/mini_player_bar.dart';
import '../player/playback_error_banner.dart';
import '../playlists/playlists_page.dart';
import '../songs/songs_page.dart';

/// 主壳：底部五 Tab——播放列表、艺术家、专辑、歌曲、更多。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 3;

  static const _pages = [
    PlaylistsPage(),
    ArtistsPage(),
    AlbumsPage(),
    SongsPage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      // 迷你播放条与错误提示挂在导航栏之上：任何 Tab 都能看到正在放什么、
      // 播放失败也能立刻看到原因，不会随页面切走而消失。
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlaybackErrorBanner(),
            MiniPlayerBar(
              // 点条身展开完整播放页（覆盖层）。覆盖层与路由属票据 09，
              // 这里先让条身可点（非 null 才是可点状态），09 接上展开。
              onTap: () {},
            ),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: '播放列表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '艺术家',
                ),
                NavigationDestination(
                  icon: Icon(Icons.album_outlined),
                  selectedIcon: Icon(Icons.album),
                  label: '专辑',
                ),
                NavigationDestination(
                  icon: Icon(Icons.music_note_outlined),
                  selectedIcon: Icon(Icons.music_note),
                  label: '歌曲',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: '更多',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

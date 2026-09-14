import 'package:flutter/material.dart';

import '../albums/albums_page.dart';
import '../artists/artists_page.dart';
import '../more/more_page.dart';
import '../playlists/playlists_page.dart';
import '../songs/songs_page.dart';

/// 一个一级导航项：标签、两个图标状态与它承载的页面。
///
/// 手机外壳（底部 Tab）与 TV 外壳（侧边导航栏）共用这一份清单：两套 chrome
/// 分叉、页面不分叉（ADR-0013 决策 1）。两处若各写一份，增删 Tab 时必然漏改
/// 一处，导航顺序也会漂移。
class HoomyDestination {
  const HoomyDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// 一级导航：播放列表、艺术家、专辑、歌曲、更多。
const kHoomyDestinations = <HoomyDestination>[
  HoomyDestination(
    label: '播放列表',
    icon: Icons.queue_music_outlined,
    selectedIcon: Icons.queue_music,
    page: PlaylistsPage(),
  ),
  HoomyDestination(
    label: '艺术家',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    page: ArtistsPage(),
  ),
  HoomyDestination(
    label: '专辑',
    icon: Icons.album_outlined,
    selectedIcon: Icons.album,
    page: AlbumsPage(),
  ),
  HoomyDestination(
    label: '歌曲',
    icon: Icons.music_note_outlined,
    selectedIcon: Icons.music_note,
    page: SongsPage(),
  ),
  HoomyDestination(
    label: '更多',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view,
    page: MorePage(),
  ),
];

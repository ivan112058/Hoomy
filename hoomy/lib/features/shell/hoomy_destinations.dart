import 'package:flutter/material.dart';

import '../albums/albums_page.dart';
import '../artists/artists_page.dart';
import '../more/genre_list_page.dart';
import '../more/more_page.dart';
import '../more/starred_songs_page.dart';
import '../playlists/playlists_page.dart';
import '../songs/songs_page.dart';

/// 一个一级导航项：标签、两个图标状态与它承载的页面。
///
/// 手机外壳（底部 Tab）与 TV 外壳（侧边导航栏）共用同一批**页面**：两套 chrome
/// 分叉、页面不分叉（ADR-0013 决策 1）。两处若各写一份页面部件，增删 Tab 时必然
/// 漏改一处；两份清单都由下面的具名目的地拼出，共享同一个页面实例。
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

/// 一级页面（具名）：两端按各自的 chrome 取用同一批。
const playlistsDestination = HoomyDestination(
  label: '播放列表',
  icon: Icons.queue_music_outlined,
  selectedIcon: Icons.queue_music,
  page: PlaylistsPage(),
);

const artistsDestination = HoomyDestination(
  label: '艺术家',
  icon: Icons.person_outline,
  selectedIcon: Icons.person,
  page: ArtistsPage(),
);

const albumsDestination = HoomyDestination(
  label: '专辑',
  icon: Icons.album_outlined,
  selectedIcon: Icons.album,
  page: AlbumsPage(),
);

const songsDestination = HoomyDestination(
  label: '歌曲',
  icon: Icons.music_note_outlined,
  selectedIcon: Icons.music_note,
  page: SongsPage(),
);

/// 「风格」：TV 上是左侧一级导航项；iOS 上仍从「更多」进。
const genresDestination = HoomyDestination(
  label: '风格',
  icon: Icons.category_outlined,
  selectedIcon: Icons.category,
  page: GenreListPage(),
);

/// 「我喜欢的歌曲」：TV 上是左侧一级导航项；iOS 上仍从「更多」进。
const starredDestination = HoomyDestination(
  label: '我喜欢的歌曲',
  icon: Icons.star_outline,
  selectedIcon: Icons.star,
  page: StarredSongsPage(),
);

/// 「更多」：iOS 底部 Tab 的最后一项，装风格与我喜欢的歌曲并给出设置入口。
///
/// TV 不需要它：那些项已经是左侧一级导航项，设置钉在导航栏底部
/// （票据 03 真机验收后按使用反馈调整）。
const moreDestination = HoomyDestination(
  label: '更多',
  icon: Icons.grid_view_outlined,
  selectedIcon: Icons.grid_view,
  page: MorePage(),
);

/// iOS（手机）底部 Tab：5 项，末项是「更多」。
const kPhoneDestinations = <HoomyDestination>[
  playlistsDestination,
  artistsDestination,
  albumsDestination,
  songsDestination,
  moreDestination,
];

/// Android TV 侧边导航栏：把「更多」里的项提上来，不再需要「更多」。
///
/// 顺序与手机一致的前四项，随后是风格与我喜欢的歌曲；设置不是页面，由
/// `TvHomeShell` 单独钉在导航栏最下面。
const kTvDestinations = <HoomyDestination>[
  playlistsDestination,
  artistsDestination,
  albumsDestination,
  songsDestination,
  genresDestination,
  starredDestination,
];

/// 歌曲在两端都是第 4 项（索引 3）：冷启动停在这里。
const kSongsDestinationIndex = 3;

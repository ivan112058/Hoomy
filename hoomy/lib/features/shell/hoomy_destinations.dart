import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../data/session/session_providers.dart';
import '../albums/albums_page.dart';
import '../artists/artists_page.dart';
import '../more/genre_list_page.dart';
import '../more/more_page.dart';
import '../more/starred_songs_page.dart';
import '../playlists/playlists_page.dart';
import '../songs/songs_page.dart';

/// 一个一级导航项：标签、两个图标状态、它承载的页面，以及它订阅的取数。
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
    this.providers = const [],
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  /// 本一级页面订阅的取数。切回本 Tab 时按这份声明失效并重取（票据 05）。
  ///
  /// 「一个 Tab 对应哪些取数」只有这一处声明：外壳只说「我切回了第 N 个 Tab」，
  /// 不点名任何 provider（ADR-0015 决策 4）。清单与页面里 `AsyncValueView` 订阅的
  /// 那条一一对应，新增一级页面时把它的取数加进来即可。
  ///
  /// 只收**常驻 `IndexedStack` 的这一页**订阅的取数：详情页（专辑／歌手／播放列表
  /// ／风格曲目）是 push 出来的层级路由，不在「已经挂载的页面」之列，且同一张专辑
  /// 还能从「艺术家」进 —— 挂在某一个 Tab 上必然漏掉另一条路径。
  final List<ProviderOrFamily> providers;

  /// 使本页面的取数失效并重取。
  void invalidateProviders(WidgetRef ref) {
    for (final provider in providers) {
      ref.invalidate(provider);
    }
  }
}

/// 一级页面（具名）：两端按各自的 chrome 取用同一批。
///
/// 目的地不是 `const`，因为它带着该页面订阅的 provider 清单（provider 实例
/// 本身不是 const）。
final playlistsDestination = HoomyDestination(
  label: '播放列表',
  icon: Icons.queue_music_outlined,
  selectedIcon: Icons.queue_music,
  page: const PlaylistsPage(),
  providers: [playlistsProvider],
);

final artistsDestination = HoomyDestination(
  label: '艺术家',
  icon: Icons.person_outline,
  selectedIcon: Icons.person,
  page: const ArtistsPage(),
  providers: [allArtistsProvider],
);

final albumsDestination = HoomyDestination(
  label: '专辑',
  icon: Icons.album_outlined,
  selectedIcon: Icons.album,
  page: const AlbumsPage(),
  providers: [allAlbumsProvider],
);

final songsDestination = HoomyDestination(
  label: '歌曲',
  icon: Icons.music_note_outlined,
  selectedIcon: Icons.music_note,
  page: const SongsPage(),
  providers: [allSongsProvider],
);

/// 「风格」：TV 上是左侧一级导航项；iOS 上仍从「更多」进。
final genresDestination = HoomyDestination(
  label: '风格',
  icon: Icons.category_outlined,
  selectedIcon: Icons.category,
  page: const GenreListPage(),
  providers: [genresProvider],
);

/// 「我喜欢的歌曲」：TV 上是左侧一级导航项；iOS 上仍从「更多」进。
final starredDestination = HoomyDestination(
  label: '我喜欢的歌曲',
  icon: Icons.star_outline,
  selectedIcon: Icons.star,
  page: const StarredSongsPage(),
  providers: [starredSongsProvider],
);

/// 「更多」：iOS 底部 Tab 的最后一项，装风格与我喜欢的歌曲并给出设置入口。
///
/// TV 不需要它：那些项已经是左侧一级导航项，设置钉在导航栏底部
/// （票据 03 真机验收后按使用反馈调整）。
///
/// 它本身不取数（只是一张菜单，子页面是 push 出来的层级路由），因此清单为空。
final moreDestination = HoomyDestination(
  label: '更多',
  icon: Icons.grid_view_outlined,
  selectedIcon: Icons.grid_view,
  page: const MorePage(),
);

/// iOS（手机）底部 Tab：5 项，末项是「更多」。
final kPhoneDestinations = <HoomyDestination>[
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
final kTvDestinations = <HoomyDestination>[
  playlistsDestination,
  artistsDestination,
  albumsDestination,
  songsDestination,
  genresDestination,
  starredDestination,
];

/// 歌曲在两端都是第 4 项（索引 3）：冷启动停在这里。
const kSongsDestinationIndex = 3;

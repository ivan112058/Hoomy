import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/session/session.dart';
import '../../data/session/session_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../albums/album_detail_page.dart';
import '../shared/album_grid_cell.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/play_rows.dart';
import '../shared/song_list_view.dart';
import '../shared/star_button.dart';

/// 从歌手列表点进歌手详情的层级导航（与 [openAlbumDetail] 同一套动效语法）。
void openArtistDetail(BuildContext context, SubsonicArtist artist) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ArtistDetailPage(artist: artist)),
  );
}

/// 歌手详情：该歌手的专辑（网格，可再点进专辑详情）与全部歌曲。
///
/// 歌手名在标题栏，头部不重复显示。**不做**参考项目的 150dp 头部大图：
/// 歌手头部没有任何图片，因此不会为它请求封面（票据 14 的定案）。
///
/// 专辑与歌曲在一个滚动页里分段呈现，不做参考项目的两个 Tab —— 票据只要求
/// 「显示该歌手的专辑与全部歌曲」。
class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({super.key, required this.artist});

  /// 列表点进来的那个歌手：`id` 用来取详情，`name` 先撑住标题栏。
  final SubsonicArtist artist;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: artist.name,
      body: AsyncValueView(
        provider: artistDetailProvider(artist.id),
        itemBuilder: (context, detail) => LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ArtistHeader(detail: detail)),
              if (detail.artist.albums.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader(title: '专辑')),
                SliverAlbumGrid(
                  albums: detail.artist.albums,
                  // 网格几何与专辑 Tab 同一份算式（[albumGridCellExtent]）。
                  cellExtent: albumGridCellExtent(constraints.maxWidth),
                  onTap: (album) => openAlbumDetail(context, album),
                ),
              ],
              const SliverToBoxAdapter(child: SectionHeader(title: '全部歌曲')),
              if (detail.songs.isEmpty)
                const SliverToBoxAdapter(child: _EmptySongs())
              else
                SongSliverList(songs: detail.songs),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌手头部：专辑数与收藏，其下两个播放入口。
class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.detail});

  final ArtistDetail detail;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final artist = detail.artist;
    // 专辑数取**已取回的那份列表**的长度：头部就贴着下面这个网格。
    final albumCount = artist.albums.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$albumCount 张专辑',
                  style: TextStyle(
                    fontSize: HoomyDimens.listTitleFontSize,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              StarButton(
                target: artistStar(artist.id),
                starred: artist.isStarred,
              ),
            ],
          ),
        ),
        // 没有曲目就不摆播放入口（同专辑详情的空态口径）。
        if (detail.songs.isNotEmpty) ...[
          PlayAllRow(songs: detail.songs),
          ShufflePlayRow(songs: detail.songs),
        ],
      ],
    );
  }
}

/// 歌手名下一首歌都没有时的空态。
class _EmptySongs extends StatelessWidget {
  const _EmptySongs();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text('这个歌手还没有歌曲')),
    );
  }
}

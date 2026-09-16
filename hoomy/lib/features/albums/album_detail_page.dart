import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/session/session_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../shared/async_view.dart';
import '../shared/cover_art.dart';
import '../shared/play_rows.dart';
import '../shared/song_count_text.dart';
import '../shared/song_list_view.dart';
import '../shared/star_button.dart';

/// 从专辑网格点进专辑详情的层级导航。
///
/// 用 [MaterialPageRoute]：从右侧推入、AppBar 自动给出返回键；全屏播放页用的是
/// 自下而上的覆盖层路由，两者是不同层级的动效语法（ADR-0003）。
void openAlbumDetail(BuildContext context, SubsonicAlbum album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AlbumDetailPage(album: album)),
  );
}

/// 专辑详情：封面、歌手、年份、曲目数量与曲目列表；可整张播放或随机播放。
///
/// 专辑名在标题栏（[PageScaffold] 的 title），头部不重复显示同一名字。
///
/// 有意**不做**参考项目的 150dp 头部大图：封面用 [CoverArt] 且不传 `size`，
/// 即专辑网格已经在用的同一份缓存身份，进入详情不额外请求一张头部大图。
/// 也不提供「加播放列表」「加队列」入口（MVP 歌单只读、队列没有写入口）。
class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({super.key, required this.album});

  /// 网格点进来的那张专辑：`id` 用来取带曲目的详情，`name` 先撑住标题栏。
  final SubsonicAlbum album;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: album.name,
      body: AsyncValueView(
        provider: albumProvider(album.id),
        itemBuilder: (context, album) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _AlbumHeader(album: album)),
            if (album.songs.isEmpty)
              const SliverToBoxAdapter(child: _EmptyTracks())
            else
              // 专辑的曲目行显示音轨号（票据 14）。
              SongSliverList(songs: album.songs, showTrackNumbers: true),
          ],
        ),
      ),
    );
  }
}

/// 头部封面尺寸：取自参考项目的专辑网格单元高度
/// `gridview_item_ccontainer_height = 116dp`（票据 03 的色值/尺寸同源）。
///
/// 只是**显示**尺寸：不把它当作 `getCoverArt` 的 `size` 下发，
/// 因此不会多出一张头部大图的请求。
const _coverSize = 116.0;

/// 专辑头部：封面 + 歌手/年份/曲目数量 + 收藏，其下两个播放入口。
class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.album});

  final SubsonicAlbum album;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final artist = album.artist;
    // 曲目数取**已取回的那份列表**的长度：头部就贴着这份列表，两者必须一致。
    // 这与票据 13 删掉的「客户端另算一个总数」不同 —— 那个数会和列表页的
    // 服务端计数并列出现，成了第二个口径；这里只有一个口径。
    final count = album.songs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _coverSize,
                height: _coverSize,
                child: CoverArt(coverArtId: album.coverArtId),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (artist != null && artist.isNotEmpty)
                      Text(
                        artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: HoomyDimens.listTitleFontSize,
                          color: palette.textPrimary,
                        ),
                      ),
                    if (album.year != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${album.year} 年',
                          style: TextStyle(
                            fontSize: HoomyDimens.listSubtitleFontSize,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SongCountText(count: count),
                    ),
                  ],
                ),
              ),
              StarButton(
                target: albumStar(album.id),
                starred: album.isStarred,
              ),
            ],
          ),
        ),
        // 没有曲目就不摆播放入口：一行看起来能点、点了却没反应比不显示更糟
        // （与播放列表详情的空态同一口径）。
        if (album.songs.isNotEmpty) ...[
          PlayAllRow(songs: album.songs),
          ShufflePlayRow(songs: album.songs),
        ],
      ],
    );
  }
}

/// 专辑里没有曲目时的空态。
class _EmptyTracks extends StatelessWidget {
  const _EmptyTracks();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text('这个专辑还没有曲目')),
    );
  }
}

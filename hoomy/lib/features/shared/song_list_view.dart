import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/subsonic/models.dart';
import '../player/playback_listenable.dart';
import 'play_song.dart';
import 'song_tile.dart';

/// 一份已取回的歌曲列表：点歌即播（播放队列就是这份列表），当前曲目高亮。
///
/// 播放列表详情、风格详情、我喜欢的歌曲三处共用这段接线，不再各自重写
/// 「当前曲目边界 + 歌曲行 + 点歌」；收藏则封在 [SongTile] 里的 `StarButton`。
///
/// [header] 是列表之上的固定部件（如「全部播放」行），不参与滚动。
/// 头部本身也要跟内容一起滚动的页面（专辑/歌手详情）用 [SongSliverList]。
class SongListView extends StatelessWidget {
  const SongListView({super.key, required this.songs, this.header});

  /// 已取回的曲目；调用方负责加载、错误与空态。
  final List<SubsonicSong> songs;

  /// 列表之上的固定部件。
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ?header,
        Expanded(
          child: CustomScrollView(slivers: [SongSliverList(songs: songs)]),
        ),
      ],
    );
  }
}

/// [SongListView] 的 sliver 形态：只渲染曲目行，供详情页与别的段落拼在
/// 同一个 [CustomScrollView] 里（头部也跟着滚，不被压在列表上方）。
///
/// 点歌、当前曲目高亮的口径与 [SongListView] 完全一致 —— 两者共用这一份。
class SongSliverList extends ConsumerWidget {
  const SongSliverList({
    super.key,
    required this.songs,
    this.showTrackNumbers = false,
  });

  final List<SubsonicSong> songs;

  /// 是否在行首显示音轨号（专辑详情用它）。
  final bool showTrackNumbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只在换歌时重建列表；进度每 ~200ms 的通知不会带累它。
    return CurrentSongIdBuilder(
      builder: (context, currentSongId) => SliverList.separated(
        itemCount: songs.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) => SongTile(
          song: songs[i],
          trackNumber: showTrackNumbers ? songs[i].track : null,
          highlighted: songs[i].id == currentSongId,
          onTap: () => playSongFromList(ref, songs, songs[i]),
        ),
      ),
    );
  }
}

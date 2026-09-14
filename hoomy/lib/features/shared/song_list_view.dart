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
/// [header] 是列表之上的固定部件（如「播放全部」行），不参与滚动。
class SongListView extends ConsumerWidget {
  const SongListView({super.key, required this.songs, this.header});

  /// 已取回的曲目；调用方负责加载、错误与空态。
  final List<SubsonicSong> songs;

  /// 列表之上的固定部件。
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ?header,
        Expanded(
          // 只在换歌时重建列表；进度每 ~200ms 的通知不会带累它。
          child: CurrentSongIdBuilder(
            builder: (context, currentSongId) => ListView.separated(
              itemCount: songs.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                highlighted: songs[i].id == currentSongId,
                onTap: () => playSongFromList(ref, songs, songs[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

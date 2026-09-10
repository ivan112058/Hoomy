import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import '../player/playback_listenable.dart';
import '../shared/async_view.dart';
import '../shared/play_song.dart';
import '../shared/song_tile.dart';

/// 我喜欢的歌曲：服务端已 star 的歌曲（收藏状态跨设备同步）。
///
/// 取消收藏由 [SongTile] 做本地乐观更新；离开本页后重新进入会重新拉取服务端状态。
/// 点歌同样出声，队列是这份收藏列表，当前曲目标播放态红（票据 06）。
class StarredSongsPage extends ConsumerWidget {
  const StarredSongsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starRepository = ref.watch(starRepositoryProvider);
    if (starRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '我喜欢的歌曲',
      body: AsyncView(
        load: starRepository.getStarredSongs,
        emptyMessage: '还没有收藏的歌曲',
        itemBuilder: (context, songs) => CurrentSongIdBuilder(
          builder: (context, currentSongId) => ListView.separated(
            itemCount: songs.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) => SongTile(
              song: songs[i],
              highlighted: songs[i].id == currentSongId,
              onTap: () => _play(ref, songs, songs[i]),
            ),
          ),
        ),
      ),
    );
  }

  void _play(WidgetRef ref, List<SubsonicSong> songs, SubsonicSong song) =>
      playSongFromList(ref, songs, song);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/song_tile.dart';

/// 我喜欢的歌曲：服务端已 star 的歌曲（收藏状态跨设备同步）。
///
/// 取消收藏由 [SongTile] 做本地乐观更新；离开本页后重新进入会重新拉取服务端状态。
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
        itemBuilder: (context, songs) => ListView.separated(
          itemCount: songs.length,
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) => SongTile(song: songs[i]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/song_list_view.dart';

/// 我喜欢的歌曲：服务端已 star 的歌曲（收藏状态跨设备同步）。
///
/// 取消收藏由 [SongTile] 里的收藏控件做乐观更新与失败回滚（票据 12）；
/// 本页不缓存状态，离开后重新进入会重新拉取服务端状态。
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
        itemBuilder: (context, songs) => SongListView(songs: songs),
      ),
    );
  }
}

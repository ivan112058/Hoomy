import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../shared/async_view.dart';
import '../shared/song_tile.dart';

/// 歌曲 Tab：全库歌曲列表。
///
/// 数据源为 `search3` 空查询（Navidrome 上等价于全库），单次取 [songLimit] 首。
/// 分页/无限滚动尚未接入，曲库超过该数量时列表会被截断 —— 待后续迭代处理。
class SongsPage extends ConsumerWidget {
  const SongsPage({super.key});

  /// 单次拉取的歌曲上限。
  static const songLimit = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(subsonicClientProvider);
    if (client == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '歌曲',
      body: AsyncView(
        future: client.search3Songs(songCount: songLimit),
        emptyMessage: '曲库是空的',
        itemBuilder: (context, songs) => ListView.separated(
          itemCount: songs.length,
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) => SongTile(song: songs[i]),
        ),
      ),
    );
  }
}

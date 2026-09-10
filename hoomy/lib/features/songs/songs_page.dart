import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/song_tile.dart';

/// 歌曲 Tab：全库歌曲列表。
///
/// 曲库经 `SongRepository` 以 `search3` 空 query 分页取全量（ADR-0005），
/// 不再有硬上限。响应不含总数，因此界面也不显示条数或页码。
class SongsPage extends ConsumerWidget {
  const SongsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songRepository = ref.watch(songRepositoryProvider);
    if (songRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '歌曲',
      body: AsyncView(
        load: songRepository.getAllSongs,
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

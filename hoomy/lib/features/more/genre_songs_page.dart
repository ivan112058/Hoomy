import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/play_rows.dart';
import '../shared/song_list_view.dart';

/// 风格详情：该风格下的曲目列表，可整单播放、可点单曲。
class GenreSongsPage extends ConsumerWidget {
  const GenreSongsPage({super.key, required this.genre});

  /// 风格名（服务端 `getGenres` 的 `value`），也是 `getSongsByGenre` 的入参。
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genreRepository = ref.watch(genreRepositoryProvider);
    if (genreRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: genre,
      body: AsyncView(
        load: () => genreRepository.getSongs(genre),
        emptyMessage: '这个风格下还没有曲目',
        itemBuilder: (context, songs) => SongListView(
          songs: songs,
          header: PlayAllRow(songs: songs),
        ),
      ),
    );
  }
}

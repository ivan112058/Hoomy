import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_count_text.dart';
import 'genre_songs_page.dart';

/// 风格列表：服务端解析出的曲库流派分组，含各自的曲目数。
///
/// 点行进入该风格的曲目列表。
class GenreListPage extends ConsumerWidget {
  const GenreListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genreRepository = ref.watch(genreRepositoryProvider);
    if (genreRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '风格',
      body: AsyncView(
        load: genreRepository.getGenres,
        emptyMessage: '曲库里还没有风格信息',
        itemBuilder: (context, genres) => ListView.separated(
          itemCount: genres.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final genre = genres[i];
            return HoomyListRow(
              title: genre.name,
              trailing: (state) =>
                  SongCountText(count: genre.songCount, state: state),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GenreSongsPage(genre: genre.name),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

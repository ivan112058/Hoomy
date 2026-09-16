import 'package:flutter/material.dart';

import '../../data/session/session_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_count_text.dart';
import 'genre_songs_page.dart';

/// 风格列表：服务端解析出的曲库流派分组，含各自的曲目数。
///
/// 曲库从**会话**取（ADR-0015 决策 1），以异步值订阅；页面不持有取数回调，
/// 也没有「没有数据源」的分支。点行进入该风格的曲目列表。
class GenreListPage extends StatelessWidget {
  const GenreListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '风格',
      body: AsyncValueView(
        provider: genresProvider,
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

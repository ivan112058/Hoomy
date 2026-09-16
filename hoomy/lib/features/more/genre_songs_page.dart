import 'package:flutter/material.dart';

import '../../data/session/session_providers.dart';
import '../shared/async_view.dart';
import '../shared/play_rows.dart';
import '../shared/song_list_view.dart';

/// 风格详情：该风格下的曲目列表，可整单播放、可点单曲。
///
/// 曲目从**会话**取（ADR-0015 决策 1），以异步值订阅；载入、失败重试与空态
/// 由 [AsyncValueView] 呈现。
class GenreSongsPage extends StatelessWidget {
  const GenreSongsPage({super.key, required this.genre});

  /// 风格名（服务端 `getGenres` 的 `value`），也是 `getSongsByGenre` 的入参。
  final String genre;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: genre,
      body: AsyncValueView(
        provider: genreSongsProvider(genre),
        emptyMessage: '这个风格下还没有曲目',
        itemBuilder: (context, songs) => SongListView(
          songs: songs,
          header: PlayAllRow(songs: songs),
        ),
      ),
    );
  }
}

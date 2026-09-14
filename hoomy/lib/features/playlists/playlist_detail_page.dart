import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import '../shared/async_view.dart';
import '../shared/play_rows.dart';
import '../shared/song_list_view.dart';

/// 播放列表详情：服务端播放列表的曲目列表，可整单播放、可点单曲。
///
/// **只读**：不提供新建、改名、删除与增删曲目（spec「范围之外」）。
/// 曲目行上的收藏是票据 12 的能力，不是播放列表的写操作。
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  /// 列表页点进来的那个播放列表：`id` 用来取详情，`name` 先撑住标题栏，
  /// 避免详情回来之前标题空一帧。
  final SubsonicPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistRepository = ref.watch(playlistRepositoryProvider);
    if (playlistRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: playlist.name,
      body: AsyncView(
        load: () async => (await playlistRepository.getPlaylist(playlist.id)).songs,
        emptyMessage: '这个播放列表还没有曲目',
        itemBuilder: (context, songs) => SongListView(
          songs: songs,
          header: PlayAllRow(songs: songs),
        ),
      ),
    );
  }
}

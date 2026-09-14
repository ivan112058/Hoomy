import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_count_text.dart';
import 'playlist_detail_page.dart';

/// 播放列表 Tab：Navidrome 服务端保存的播放列表（MVP 只读）。
///
/// 行显示列表名与曲目数；点行进入详情看曲目。新建／改名／删除／增删曲目
/// 均不在 MVP 范围内，本页没有任何写入口。
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistRepository = ref.watch(playlistRepositoryProvider);
    if (playlistRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '播放列表',
      body: AsyncView(
        load: playlistRepository.getPlaylists,
        emptyMessage: '服务器上还没有播放列表',
        itemBuilder: (context, playlists) => ListView.separated(
          itemCount: playlists.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final playlist = playlists[i];
            final owner = playlist.owner;
            return HoomyListRow(
              title: playlist.name,
              subtitle: owner == null ? null : '创建者：$owner',
              trailing: (state) =>
                  SongCountText(count: playlist.songCount, state: state),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetailPage(playlist: playlist),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

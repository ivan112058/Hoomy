import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';

/// 播放列表 Tab：Navidrome 服务端歌单（MVP 只读）。
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
        emptyMessage: '服务器上还没有歌单',
        itemBuilder: (context, playlists) => ListView.separated(
          itemCount: playlists.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final playlist = playlists[i];
            final owner = playlist.owner;
            return HoomyListRow(
              title: playlist.name,
              subtitle: owner == null ? null : 'by $owner',
              trailing: (state) => Text(
                '${playlist.songCount ?? 0} 首',
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  color: state.foreground,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

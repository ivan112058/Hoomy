import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';

/// 播放列表 Tab：Navidrome 服务端歌单（MVP 只读）。
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistRepositoryProvider);
    if (playlists == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '播放列表',
      body: AsyncView(
        load: playlists.getPlaylists,
        emptyMessage: '服务器上还没有歌单',
        itemBuilder: (context, list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) {
            final playlist = list[i];
            return ListTile(
              title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: playlist.owner == null ? null : Text('by ${playlist.owner}'),
              trailing: Text('${playlist.songCount ?? 0} 首'),
            );
          },
        ),
      ),
    );
  }
}

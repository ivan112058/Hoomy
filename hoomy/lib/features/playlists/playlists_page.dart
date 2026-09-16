import 'package:flutter/material.dart';

import '../../data/session/session_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_count_text.dart';
import 'playlist_detail_page.dart';

/// 播放列表 Tab：Navidrome 服务端保存的播放列表（MVP 只读）。
///
/// 曲库从**会话**取（ADR-0015 决策 1），以异步值订阅；页面不持有取数回调，
/// 也没有「没有数据源」的分支。行显示列表名与曲目数；点行进入详情看曲目。
/// 新建／改名／删除／增删曲目均不在 MVP 范围内，本页没有任何写入口。
class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '播放列表',
      body: AsyncValueView(
        provider: playlistsProvider,
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

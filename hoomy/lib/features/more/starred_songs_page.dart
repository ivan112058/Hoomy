import 'package:flutter/material.dart';

import '../../data/session/session_providers.dart';
import '../shared/async_view.dart';
import '../shared/song_list_view.dart';

/// 我喜欢的歌曲：服务端已 star 的歌曲（收藏状态跨设备同步）。
///
/// 曲目从**会话**取（ADR-0015 决策 1），以异步值订阅；页面不持有取数回调，
/// 也没有「没有数据源」的分支。取消收藏由 [SongTile] 里的收藏控件做乐观更新
/// 与失败回滚（票据 12）；本页不缓存状态，离开后重新进入会重新拉取服务端状态。
/// 点歌同样出声，队列是这份收藏列表，当前曲目标播放态红（票据 06）。
class StarredSongsPage extends StatelessWidget {
  const StarredSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '我喜欢的歌曲',
      body: AsyncValueView(
        provider: starredSongsProvider,
        emptyMessage: '还没有收藏的歌曲',
        itemBuilder: (context, songs) => SongListView(songs: songs),
      ),
    );
  }
}

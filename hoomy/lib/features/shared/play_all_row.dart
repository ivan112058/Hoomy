import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/subsonic/models.dart';
import 'hoomy_list_row.dart';
import 'play_song.dart';

/// 「播放全部」行：以整份列表为队列，从第一首开始播。
///
/// 队列就是这份列表，因此播完第一首会顺着往下走（spec 用户故事 24）。
/// 空列表时不可点（仍是普通行，保留按压反馈），`first` 因此始终安全。
class PlayAllRow extends ConsumerWidget {
  const PlayAllRow({super.key, required this.songs});

  final List<SubsonicSong> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HoomyListRow(
      title: '播放全部',
      leading: const Icon(Icons.play_arrow),
      onTap: songs.isEmpty
          ? null
          : () => playSongFromList(ref, songs, songs.first),
    );
  }
}

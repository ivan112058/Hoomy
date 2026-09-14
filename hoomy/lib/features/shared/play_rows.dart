import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/subsonic/models.dart';
import '../../player/playback_controller.dart';
import '../../player/player_providers.dart';
import 'hoomy_list_row.dart';

/// 详情页的两个播放入口：都以**整份列表**为播放队列（spec 用户故事 24）。
///
/// 两行的形状（图标 + 文案 + 空列表不可点）一样，差别只在交给控制器的意图：
/// 「全部播放」关随机、从第一首起；「随机播放」开随机、从随机的某一首起。
/// 意图封在 [PlaybackController.playAll] / [PlaybackController.playShuffled]，
/// 界面只负责在哪儿点。
///
/// 文案取自参考项目的 `play_all` =「全部播放」、`play_shuffle` =「随机播放」。
class PlayAllRow extends StatelessWidget {
  const PlayAllRow({super.key, required this.songs});

  final List<SubsonicSong> songs;

  @override
  Widget build(BuildContext context) => _PlayListRow(
    title: '全部播放',
    icon: Icons.play_arrow,
    songs: songs,
    play: (controller, songs) => controller.playAll(songs),
  );
}

/// 「随机播放」行：打开随机，并从其中随机一首开始。
class ShufflePlayRow extends StatelessWidget {
  const ShufflePlayRow({super.key, required this.songs});

  final List<SubsonicSong> songs;

  @override
  Widget build(BuildContext context) => _PlayListRow(
    title: '随机播放',
    icon: Icons.shuffle,
    songs: songs,
    play: (controller, songs) => controller.playShuffled(songs),
  );
}

class _PlayListRow extends ConsumerWidget {
  const _PlayListRow({
    required this.title,
    required this.icon,
    required this.songs,
    required this.play,
  });

  final String title;
  final IconData icon;
  final List<SubsonicSong> songs;
  final void Function(PlaybackController controller, List<SubsonicSong> songs)
  play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HoomyListRow(
      title: title,
      leading: Icon(icon),
      // 空列表时不可点（仍是普通行，保留按压反馈）。
      onTap: songs.isEmpty
          ? null
          : () {
              final controller = ref.read(playerControllerProvider);
              if (controller == null) return;
              play(controller, songs);
            },
    );
  }
}

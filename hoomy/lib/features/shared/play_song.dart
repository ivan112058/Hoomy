import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/subsonic/models.dart';
import '../../player/player_providers.dart';

/// 点一首歌即播放：以 [visible]（用户当前看到的整份列表）为播放队列，
/// 从 [song] 开始。
///
/// 队列就是**当前可见的上下文** —— 搜索过滤后点歌，队列是过滤后的结果
/// （spec 用户故事 24：点一首之后能在当前上下文里连续听下去）。
///
/// 歌曲列表页共用这一处：歌曲 Tab 与我喜欢的歌曲都走它，免得各自记一遍
/// 「队列取哪份列表、起点怎么算」。
void playSongFromList(
  WidgetRef ref,
  List<SubsonicSong> visible,
  SubsonicSong song,
) {
  final controller = ref.read(playerControllerProvider);
  if (controller == null) return;
  final index = visible.indexOf(song);
  controller.playQueue(visible, startIndex: index < 0 ? 0 : index);
}

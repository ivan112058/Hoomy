import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_providers.dart';
import '../player/playback_page.dart';

/// 从主壳展开全屏播放页（点迷你播放条）。
///
/// 手机底部 Tab 外壳与 TV 侧边导航外壳共用这一处：ADR-0013 只允许导航 chrome
/// 分叉，接线逻辑两处各写一遍迟早会漂。没有控制器（未登录）时不做任何事。
void openPlaybackFromShell(BuildContext context, WidgetRef ref) {
  final controller = ref.read(playerControllerProvider);
  if (controller == null) return;
  Navigator.of(context).push(playbackPageRoute(controller));
}

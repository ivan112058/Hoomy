import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_controller.dart';
import 'just_audio_player_engine.dart';
import 'playback_controller.dart';
import 'player_engine.dart';
import 'stream_uri.dart';

/// 当前登录会话的 `stream` 地址解析器（`format=raw` + 认证查询串）。
///
/// 未登录时为 null —— 没有服务器就没有可播放的地址。
final streamUriResolverProvider = Provider<StreamUriResolver?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client?.streamUri;
});

/// 真实播放引擎（`just_audio`，ADR-0010）。
///
/// 提供 override 接缝：widget 测试把 [playerEngineProvider] 换成
/// `FakePlayerEngine`，就能在不碰音频设备的前提下验证「点歌 → 播放」的接线。
final playerEngineProvider = Provider<PlayerEngine?>((ref) {
  if (ref.watch(streamUriResolverProvider) == null) return null;
  return JustAudioPlayerEngine();
});

/// 播放接线：状态机 + 引擎，界面唯一的播放入口。
final playerControllerProvider = Provider<PlaybackController?>((ref) {
  final engine = ref.watch(playerEngineProvider);
  final streamUriOf = ref.watch(streamUriResolverProvider);
  if (engine == null || streamUriOf == null) return null;
  final controller = PlaybackController(
    engine: engine,
    streamUriOf: streamUriOf,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

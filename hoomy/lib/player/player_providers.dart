import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_controller.dart';
import 'hoomy_audio_handler.dart';
import 'just_audio_player_engine.dart';
import 'playback_audio_session.dart';
import 'playback_controller.dart';
import 'player_engine.dart';
import 'stream_uri.dart';

/// 系统媒体会话（`audio_service`，ADR-0008）。
///
/// 生产在 `main()` 里 `AudioService.init` 之后 override；widget 测试与初始化
/// 失败时为 null —— 不触达平台通道，播放仍可在前台工作，只是没有系统媒体控制。
final audioHandlerProvider = Provider<HoomyAudioHandler?>((ref) => null);

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
///
/// 控制器创建后立刻接两处（票据 07）：
/// - **系统媒体会话**：挂到 [audioHandlerProvider]，系统媒体键经它进来，
///   播放状态经它出去。
/// - **音频会话**：`audio_session` 在引擎（音频初始化）之后配置音乐类别，
///   并订阅打断与耳机拔出。
final playerControllerProvider = Provider<PlaybackController?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  final engine = ref.watch(playerEngineProvider);
  final streamUriOf = ref.watch(streamUriResolverProvider);
  if (client == null || engine == null || streamUriOf == null) return null;

  final controller = PlaybackController(
    engine: engine,
    streamUriOf: streamUriOf,
  );
  ref
      .watch(audioHandlerProvider)
      ?.attach(controller, coverArtUriOf: client.coverArtUri);

  // 音频会话接线是异步的（要取平台全局会话）；期间若控制器已被释放，
  // 就地把刚建立的监听丢掉，不留悬挂订阅。
  var disposed = false;
  PlaybackAudioSession? audioSession;
  unawaited(() async {
    try {
      final session = await PlaybackAudioSession.attach(controller);
      if (disposed) {
        session.dispose();
        return;
      }
      audioSession = session;
    } catch (_) {
      // 平台没有音频会话能力（或测试环境）：降级为仅前台播放。
    }
  }());

  ref.onDispose(() {
    disposed = true;
    audioSession?.dispose();
    controller.dispose();
  });
  return controller;
});

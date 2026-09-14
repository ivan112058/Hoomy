import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_controller.dart';
import 'hoomy_audio_handler.dart';
import 'just_audio_player_engine.dart';
import 'playback_audio_session.dart';
import 'playback_controller.dart';
import 'player_engine.dart';
import 'queue_store.dart';
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

/// 播放队列的持久化存储（票据 11）。
///
/// 测试可 override 成注入 `SharedPreferences` 的实例，避免触达平台通道。
final queueStoreProvider = Provider<QueueStore>((ref) => QueueStore());

/// 播放接线：状态机 + 引擎，界面唯一的播放入口。
///
/// 控制器创建后立刻接两处（票据 07）：
/// - **系统媒体会话**：生产由 [audioHandlerProvider] **创建并持有**控制器
///   （ADR-0008 的权威持有者），这里拿到的是它持有的那一个；测试与无系统
///   集成时直接建控制器，行为不变。
/// - **音频会话**：`audio_session` 在引擎（音频初始化）之后配置音乐类别，
///   并订阅打断与耳机拔出。
///
/// ADR-0008 说「界面从 audio_service 读状态」在本项目落地为：界面读的控制器由
/// handler 创建并持有，界面从不触达 `just_audio` 内核；进度每 ~200ms 的高频更新
/// 仍由控制器承担，不把系统状态流当进度源（audio_service 的 `PlaybackState`
/// 只在状态变化时发布）。
///
/// 控制器同时负责队列持久化（票据 11）：创建后异步 [PlaybackController.restore]
/// 上次的队列，恢复为暂停态，不打断启动。
final playerControllerProvider = Provider<PlaybackController?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  final engine = ref.watch(playerEngineProvider);
  final streamUriOf = ref.watch(streamUriResolverProvider);
  if (client == null || engine == null || streamUriOf == null) return null;

  final queueStore = ref.watch(queueStoreProvider);
  final handler = ref.watch(audioHandlerProvider);
  final controller =
      handler?.attach(
        engine: engine,
        streamUriOf: streamUriOf,
        coverArtUriOf: client.coverArtUri,
        queueStore: queueStore,
      ) ??
      PlaybackController(
        engine: engine,
        streamUriOf: streamUriOf,
        queueStore: queueStore,
      );

  // 读回上次的队列（若在）：恢复是异步的，界面先以空队列起步，读完即更新。
  unawaited(controller.restore());

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
    } catch (e) {
      // 平台没有音频会话能力（或测试环境）：降级为仅前台播放。打断与耳机拔出
      // 保护因此不可用，但没有可呈现给用户的位置，留日志供定位。
      debugPrint('音频会话接线失败，打断与耳机拔出保护不可用：$e');
    }
  }());

  ref.onDispose(() {
    disposed = true;
    audioSession?.dispose();
    handler?.detach(controller);
    controller.dispose();
  });
  return controller;
});

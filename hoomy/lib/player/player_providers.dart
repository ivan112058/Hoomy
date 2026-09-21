import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session/session_providers.dart';
import 'hoomy_audio_handler.dart';
import 'just_audio_player_engine.dart';
import 'playback_audio_session.dart';
import 'playback_controller.dart';
import 'player_engine.dart';
import 'queue_store.dart';

/// 系统媒体会话（`audio_service`，ADR-0008）。
///
/// 生产在 `main()` 里 `AudioService.init` 之后 override；widget 测试与初始化
/// 失败时为 null —— 不触达平台通道，播放仍可在前台工作，只是没有系统媒体控制。
final audioHandlerProvider = Provider<HoomyAudioHandler?>((ref) => null);

/// 真实播放引擎（`just_audio`，ADR-0010）。
///
/// **与会话无关**：引擎构造不需要会话，这里也不再拿「有没有地址解析器」冒充
/// 「已登录」开关（ADR-0015 决策 1 的后果）。会话只供两个地址函数，由
/// [playerControllerProvider] 取用。
///
/// 可空是**测试接缝**（与 [audioHandlerProvider] 同一手法）：widget 测试置空，
/// 于是不构造 `just_audio` 平台插件、也不建控制器；生产恒为真实引擎，因此
/// [playerControllerProvider] 里的 `engine == null` 分支只在测试里走。
final playerEngineProvider = Provider<PlayerEngine?>(
  (ref) => JustAudioPlayerEngine(),
);

/// 播放队列的持久化存储（票据 11）。
///
/// 测试可 override 成注入 `SharedPreferences` 的实例，避免触达平台通道。
final queueStoreProvider = Provider<QueueStore>((ref) => QueueStore());

/// 播放接线：状态机 + 引擎 + 会话提供的两个地址，界面唯一的播放入口。
///
/// 两个地址函数（歌曲播放地址、封面地址）来自**会话**（ADR-0015 决策 1）：
/// 播放层因此不再认识协议客户端，协议词汇也不再漏进来。
///
/// 会话读的是可空形态 [sessionOrNullProvider]：没有会话时**控制器为空、引擎
/// 也不构造**（与改动前一致）。它有两条来路 —— 生产里外壳只在登录闸口之下
/// 挂载，因此未登录时根本没人读本 provider；而「不变量被破坏」的用例（绕过
/// 闸口直接挂外壳）也能如实得到空控制器，不会把异常漏出外壳的统一兜底。
///
/// 声明 `dependencies` 与取数 provider 同理：会话是在登录闸口的**嵌套作用域**
/// 里注入的，只有静态声明依赖，Riverpod 才知道该把本 provider 放进那个作用域。
/// 随之而来的好处是生命周期对齐 —— 退出登录时作用域释放，控制器与系统媒体
/// 会话一并解挂。
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
final playerControllerProvider = Provider<PlaybackController?>(
  (ref) {
    // 先要会话：没有会话就没有可播放的地址，引擎也无需构造。
    final session = ref.watch(sessionOrNullProvider);
    if (session == null) return null;
    final engine = ref.watch(playerEngineProvider);
    if (engine == null) return null;

    final queueStore = ref.watch(queueStoreProvider);
    final handler = ref.watch(audioHandlerProvider);
    final controller =
        handler?.attach(
          engine: engine,
          streamUriOf: session.streamUri,
          coverArtUriOf: session.coverArtUri,
          queueStore: queueStore,
        ) ??
        PlaybackController(
          engine: engine,
          streamUriOf: session.streamUri,
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
        final binding = await PlaybackAudioSession.attach(controller);
        if (disposed) {
          binding.dispose();
          return;
        }
        audioSession = binding;
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
  },
  dependencies: [sessionOrNullProvider],
);

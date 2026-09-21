import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'playback_controller.dart';

/// 音频会话接线（ADR-0008）：音乐类别配置 + 打断处理 + 耳机拔出。
///
/// `just_audio` 不自带这些行为，必须由应用订阅并翻译成播放命令。
///
/// 打断与设备事件用**流**注入而不是直接取全局 [AudioSession]：这些逻辑与平台
/// 通道无关，注入后可以脱离设备测试（票据 07 的验收项之一就是打断与拔出）。
class PlaybackAudioSession {
  PlaybackAudioSession(
    this._controller, {
    required Stream<AudioInterruptionEvent> interruptions,
    required Stream<void> becomingNoisy,
  }) {
    _interruptionSub = interruptions.listen(_onInterruption);
    _noisySub = becomingNoisy.listen(_onNoisy);
  }

  /// 生产接线：取全局音频会话，**在音频初始化之后**配置音乐类别，再开始监听。
  ///
  /// `just_audio` 的 `AudioPlayer` 构造时已建立音频会话，因此这里必须晚于引擎
  /// 构造 —— 由 `playerControllerProvider` 保证调用时机。
  static Future<PlaybackAudioSession> attach(
    PlaybackController controller,
  ) async {
    final session = await AudioSession.instance;
    // 先订阅再配置：配置本身是异步的，早订阅可以缩小「开始播放但音乐类别尚未
    // 落定」的窗口。
    final binding = PlaybackAudioSession(
      controller,
      interruptions: session.interruptionEventStream,
      becomingNoisy: session.becomingNoisyEventStream,
    );
    await session.configure(const AudioSessionConfiguration.music());
    return binding;
  }

  /// duck 打断期间压到的音量。
  static const _duckedVolume = 0.3;

  final PlaybackController _controller;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  /// 被打断前是否正在播放：只有当时在播，打断结束才恢复。
  bool _wasPlaying = false;

  /// 是否正因 duck 打断而压低音量。
  bool _ducked = false;

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (!_ducked && _controller.snapshot.playing) {
            _ducked = true;
            unawaited(_controller.setVolume(_duckedVolume));
          }
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _wasPlaying = _controller.snapshot.playing;
          if (_wasPlaying) unawaited(_controller.pause());
      }
      return;
    }

    // 打断结束：按「打断前是否在播」恢复，用户自己按下的暂停不会被顶掉。
    switch (event.type) {
      case AudioInterruptionType.duck:
        if (_ducked) {
          _ducked = false;
          unawaited(_controller.setVolume(1));
        }
      case AudioInterruptionType.pause:
      case AudioInterruptionType.unknown:
        final resume = _wasPlaying;
        _wasPlaying = false;
        if (resume) unawaited(_controller.play());
    }
  }

  /// 耳机拔出：暂停，且不自动恢复。清掉待恢复标记，避免随后的打断结束把它顶回来。
  void _onNoisy(void _) {
    _wasPlaying = false;
    unawaited(_controller.pause());
  }

  /// 停止监听。之后不再响应打断与耳机拔出。
  void dispose() {
    _interruptionSub?.cancel();
    _noisySub?.cancel();
    _interruptionSub = null;
    _noisySub = null;
  }
}

import 'dart:async';

/// S2 接缝：播放引擎。
///
/// 只抽象「播放一个音频源」的原子能力 —— 加载曲目、播放、暂停、跳转、音量、
/// 播放位置与状态流、播放完成事件。队列推进、循环、随机等业务规则不在这里，
/// 而在其上的 `PlaybackStateMachine`。
///
/// 本文件不引用任何具体音频库，实现（`just_audio` 等，见 ADR-0010）在别处；
/// 状态机与界面都只依赖这个接口，规则因此可脱离音频设备测试。
abstract interface class PlayerEngine {
  /// 当前播放位置。
  Stream<Duration> get positionStream;

  /// 播放状态快照流（是否在播、加载阶段、时长）。
  Stream<PlayerEngineState> get stateStream;

  /// 一首曲目自然播放结束的**事件**流，用于推进队列。
  ///
  /// 与 [PlayerEngineState.status] 的 `completed` 描述同一时刻：事件驱动队列
  /// 推进，状态供界面呈现。引擎对同一曲目的结束只应上报一次。
  Stream<void> get completionStream;

  /// 播放失败事件流，携带可直接呈现给用户的文案。
  ///
  /// 加载、解码、播放中任何一环失败都走这里，界面据此提示，不静默失败。
  Stream<PlayerEngineError> get errorStream;

  /// 加载 [uri] 指向的音频并停在起点，不自动播放。
  ///
  /// 加载阶段失败以 [errorStream] 上报，不以异常形式抛出 —— 调用方是状态机，
  /// 它没有呈现错误的位置。
  Future<void> load(Uri uri);

  /// 开始或继续播放。
  Future<void> play();

  /// 暂停播放。
  Future<void> pause();

  /// 跳转到 [position]。
  Future<void> seek(Duration position);

  /// 设置音量，取值 0.0–1.0。
  Future<void> setVolume(double volume);

  /// 释放底层资源，之后不再收到任何事件。
  Future<void> dispose();
}

/// 一次播放失败：可读文案 + 可选的引擎原始描述。
///
/// [message] 面向用户（中文），[detail] 面向开发者定位（如 `(1) ...`）。
class PlayerEngineError {
  const PlayerEngineError(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}

/// 播放引擎的加载阶段。
enum PlayerEngineStatus {
  /// 未加载任何音频。
  idle,

  /// 正在加载或缓冲。
  loading,

  /// 已就绪：可播放或正在播放。
  ready,

  /// 当前曲目已播放到结尾（与 [PlayerEngine.completionStream] 对应）。
  completed,
}

/// 播放引擎的瞬时状态快照。
class PlayerEngineState {
  const PlayerEngineState({
    required this.playing,
    required this.status,
    this.duration,
  });

  /// 未加载任何音频时的初始状态。
  static const idle = PlayerEngineState(
    playing: false,
    status: PlayerEngineStatus.idle,
  );

  final bool playing;
  final PlayerEngineStatus status;

  /// 当前曲目总时长；未知时为 null。
  final Duration? duration;
}

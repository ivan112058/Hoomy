import 'dart:async';

import 'package:hoomy/player/player_engine.dart';

/// S2 接缝（`PlayerEngine`）的测试基座：假引擎不含任何音频库，
/// 于是队列推进、循环、随机等规则可以脱离音频设备验证。
///
/// 事件控制器用 `sync: true`，让「引擎报告播完」到「状态机推进」在同一个
/// 事件循环里发生，测试只需 `pumpEventQueue()` 即可等到推进完成。
class FakePlayerEngine implements PlayerEngine {
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _state = StreamController<PlayerEngineState>.broadcast(sync: true);
  final _completion = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<PlayerEngineError>.broadcast(sync: true);

  /// 依次加载过的曲目 id（取自 stream uri 的 `id` 参数）。
  final List<String> loadedIds = [];

  /// 依次加载过的完整地址，用于断言 `format=raw` 与认证查询串。
  final List<Uri> loadedUris = [];

  int playCount = 0;
  int pauseCount = 0;
  final List<Duration> seeks = [];
  final List<double> volumes = [];
  bool disposed = false;

  /// 本引擎的四条流上是否还挂着订阅。
  ///
  /// 释放类用例据此断言订阅**真的**解除了 —— 只看 [disposed] 分不清「取消了订阅」
  /// 与「留着订阅、靠下游的 `_disposed` 兜住」。
  bool get hasListeners =>
      _state.hasListener ||
      _position.hasListener ||
      _completion.hasListener ||
      _errors.hasListener;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<PlayerEngineState> get stateStream => _state.stream;

  @override
  Stream<void> get completionStream => _completion.stream;

  @override
  Stream<PlayerEngineError> get errorStream => _errors.stream;

  @override
  Future<void> load(Uri uri) async {
    loadedUris.add(uri);
    loadedIds.add(uri.queryParameters['id'] ?? '');
  }

  @override
  Future<void> play() async {
    playCount++;
    // 与真引擎一致：play 后状态变为「正在播放」。
    emitState(
      PlayerEngineState(
        playing: true,
        status: currentStatus,
        duration: currentDuration,
      ),
    );
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    // 与真引擎一致：pause 后状态变为「已暂停」。
    emitState(
      PlayerEngineState(
        playing: false,
        status: currentStatus,
        duration: currentDuration,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _position.close();
    await _state.close();
    await _completion.close();
    await _errors.close();
  }

  /// 模拟当前曲目自然播放结束。
  void complete() => _completion.add(null);

  /// 模拟引擎上报一次播放失败。
  void fail(String message, {String? detail}) =>
      _errors.add(PlayerEngineError(message, detail: detail));

  /// 模拟播放位置推进。
  void emitPosition(Duration position) => _position.add(position);

  /// 模拟播放状态变化。
  void emitState(PlayerEngineState state) {
    currentStatus = state.status;
    currentDuration = state.duration;
    _state.add(state);
  }

  /// 最近一次上报的加载阶段。
  PlayerEngineStatus currentStatus = PlayerEngineStatus.idle;

  /// 最近一次上报的时长。
  Duration? currentDuration;

  /// 最近一次加载的曲目 id。
  String? get lastLoadedId => loadedIds.isEmpty ? null : loadedIds.last;

  /// 最近一次加载的完整地址。
  Uri? get lastLoadedUri => loadedUris.isEmpty ? null : loadedUris.last;
}

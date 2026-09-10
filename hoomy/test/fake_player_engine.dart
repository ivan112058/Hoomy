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

  /// 依次加载过的曲目 id（取自 stream uri 的 `id` 参数）。
  final List<String> loadedIds = [];

  int playCount = 0;
  int pauseCount = 0;
  final List<Duration> seeks = [];
  final List<double> volumes = [];
  bool disposed = false;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<PlayerEngineState> get stateStream => _state.stream;

  @override
  Stream<void> get completionStream => _completion.stream;

  @override
  Future<void> load(Uri uri) async {
    loadedIds.add(uri.queryParameters['id'] ?? '');
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
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
  }

  /// 模拟当前曲目自然播放结束。
  void complete() => _completion.add(null);

  /// 最近一次加载的曲目 id。
  String? get lastLoadedId => loadedIds.isEmpty ? null : loadedIds.last;
}

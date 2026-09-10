import 'dart:async';
import 'dart:math';

import '../data/subsonic/models.dart';
import 'player_engine.dart';
import 'stream_uri.dart';

/// 循环模式。
enum RepeatMode {
  /// 播完最后一首停止。
  off,

  /// 播完最后一首回到第一首。
  all,

  /// 播完重播同一首，不推进索引。
  one,
}

/// 队列状态快照：队列内容、当前曲目下标、循环与随机模式。
class PlaybackQueueState {
  const PlaybackQueueState({
    required this.queue,
    required this.currentIndex,
    required this.repeatMode,
    required this.shuffle,
  });

  /// 空队列的初始状态。
  static const empty = PlaybackQueueState(
    queue: <SubsonicSong>[],
    currentIndex: -1,
    repeatMode: RepeatMode.off,
    shuffle: false,
  );

  /// 当前播放上下文（专辑曲目／歌手全部歌曲／播放列表曲目／搜索结果）。
  final List<SubsonicSong> queue;

  /// 当前曲目在 [queue] 中的下标；空队列为 -1。
  final int currentIndex;

  final RepeatMode repeatMode;
  final bool shuffle;

  SubsonicSong? get currentSong =>
      currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
}

/// 播放状态机：持有队列、当前索引、循环模式与随机模式，并驱动 [PlayerEngine]。
///
/// 队列规则是本项目最复杂的业务逻辑，因此与具体音频库解耦（S2）：本文件是纯
/// Dart，只通过 [PlayerEngine] 触达音频设备，可用假引擎完整测试。
///
/// 规则约定：
/// - **顺序**：随机关闭时是队列自然序；随机打开时是队列下标的一份随机排列。
/// - **自动推进**（一曲自然播完）：单曲循环重播当前曲、不推进索引；否则按顺序
///   前进一首，走到尽头时全部循环回绕、循环关闭停止。
/// - **手动切歌**：与自动推进共用同一套顺序与回绕规则；唯一区别是单曲循环 ——
///   手动切歌是明确的换歌请求，仍按顺序移动（`one` 不改手动落点）。
/// - **随机的一轮**：一轮是队列下标的一份随机排列，`playQueue` 或中途打开随机
///   都会以当前曲目为起点开一轮，一轮内每首至多一次。全部循环下一轮走完后
///   重新洗牌开新一轮，并避免新一轮第一首就是刚播完的那首。
class PlaybackStateMachine {
  PlaybackStateMachine(this._engine, this._streamUriOf, {Random? random})
    : _random = random ?? Random() {
    _completionSub = _engine.completionStream.listen(
      (_) => unawaited(_onCompleted()),
    );
    _errorSub = _engine.errorStream.listen(_errors.add);
  }

  final PlayerEngine _engine;
  final StreamUriResolver _streamUriOf;
  final Random _random;
  StreamSubscription<void>? _completionSub;
  StreamSubscription<PlayerEngineError>? _errorSub;

  List<SubsonicSong> _queue = const [];

  /// 播放顺序：队列下标的一份排列。
  List<int> _playOrder = const [];

  /// 当前曲目在 [_playOrder] 中的游标；空队列为 -1。
  int _playOrderCursor = -1;

  RepeatMode _repeat = RepeatMode.off;
  bool _shuffle = false;

  /// 防重入：引擎若对同一曲目重复上报结束，只推进一次。
  bool _handlingCompletion = false;

  PlaybackQueueState _state = PlaybackQueueState.empty;
  final _states = StreamController<PlaybackQueueState>.broadcast();

  /// 播放失败事件流，直接转发自引擎（文案已由引擎翻译好）。
  ///
  /// 状态机自身不产生错误：队列规则（推进、循环、随机）与音频设备无关，
  /// 失败只可能来自引擎的加载／解码／网络。
  final _errors = StreamController<PlayerEngineError>.broadcast();

  /// 当前队列状态。
  PlaybackQueueState get state => _state;

  /// 队列状态变化流。
  Stream<PlaybackQueueState> get stateStream => _states.stream;

  /// 播放失败事件流，供界面提示。
  Stream<PlayerEngineError> get errorStream => _errors.stream;

  /// 当前曲目在队列中的下标；空队列为 -1。
  int get _currentIndex =>
      _playOrderCursor >= 0 && _playOrderCursor < _playOrder.length
      ? _playOrder[_playOrderCursor]
      : -1;

  /// 用 [songs] 作为播放队列（当前曲目所在的上下文），并从 [startIndex] 开始播放。
  ///
  /// [startIndex] 越界时收敛到合法范围。空队列表示停止播放并清空当前曲目。
  Future<void> playQueue(List<SubsonicSong> songs, {int startIndex = 0}) async {
    _queue = List.unmodifiable(songs);
    if (_queue.isEmpty) {
      _playOrder = const [];
      _playOrderCursor = -1;
      _publish();
      await _engine.pause();
      return;
    }

    final start = startIndex.clamp(0, _queue.length - 1);
    _playOrder = _orderedFrom(start);
    // 随机关闭时顺序是自然序，当前曲目就落在它自己的下标上；
    // 随机打开时 [start] 被排到一轮之首。
    _playOrderCursor = _shuffle ? 0 : start;
    _publish();
    await _loadCurrent(autoplay: true);
  }

  /// 开始或继续播放当前曲目。
  Future<void> play() => _engine.play();

  /// 暂停当前曲目。
  Future<void> pause() => _engine.pause();

  /// 手动切到下一首；到尽头且不循环时无操作。
  Future<void> next() => _move(1);

  /// 手动切到上一首；到尽头且不循环时无操作。
  Future<void> previous() => _move(-1);

  /// 切换循环模式；不改变当前曲目。
  void setRepeatMode(RepeatMode mode) {
    if (mode == _repeat) return;
    _repeat = mode;
    _publish();
  }

  /// 切换随机模式；当前曲目保持不变，其余曲目排成新的一轮。
  void setShuffle(bool enabled) {
    if (enabled == _shuffle) return;
    final current = _currentIndex;
    _shuffle = enabled;
    if (_queue.isEmpty) {
      _playOrder = const [];
      _playOrderCursor = -1;
    } else if (enabled) {
      // 当前曲目留在原位，其余洗牌排到它后面。
      _playOrder = _orderedFrom(current);
      _playOrderCursor = 0;
    } else {
      // 回到自然序，并定位回当前曲目。
      _playOrder = _naturalOrder();
      _playOrderCursor = current;
    }
    _publish();
  }

  /// 释放订阅与引擎。
  Future<void> dispose() async {
    await _completionSub?.cancel();
    _completionSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    await _states.close();
    await _errors.close();
    await _engine.dispose();
  }

  /// 队列下标的自然序。
  List<int> _naturalOrder() => [for (var i = 0; i < _queue.length; i++) i];

  /// 以 [start] 为首构造一轮播放顺序。随机关闭时为自然序。
  List<int> _orderedFrom(int start) {
    final indices = _naturalOrder();
    if (!_shuffle) return indices;
    indices.remove(start);
    indices.shuffle(_random);
    return [start, ...indices];
  }

  /// 重新洗牌开下一轮：避免新一轮的第一首就是刚播完的那首。
  void _reshuffle() {
    final lastPlayed = _currentIndex;
    final indices = _naturalOrder()..shuffle(_random);
    if (indices.length > 1 && indices.first == lastPlayed) {
      final first = indices[0];
      indices[0] = indices[1];
      indices[1] = first;
    }
    _playOrder = indices;
    _playOrderCursor = 0;
  }

  /// 一曲自然播完后的落点：单曲循环重播，否则前进一首。
  Future<void> _onCompleted() async {
    if (_handlingCompletion) return;
    _handlingCompletion = true;
    try {
      if (_queue.isEmpty) return;
      if (_repeat == RepeatMode.one) {
        await _engine.seek(Duration.zero);
        await _engine.play();
        return;
      }
      await _move(1);
    } finally {
      _handlingCompletion = false;
    }
  }

  /// 在播放顺序里移动 [delta] 步；到尽头且不循环时不动作。
  Future<void> _move(int delta) async {
    if (_queue.isEmpty) return;

    if (delta > 0) {
      if (_playOrderCursor + 1 < _playOrder.length) {
        _playOrderCursor++;
      } else if (_repeat == RepeatMode.all) {
        if (_shuffle) {
          _reshuffle();
        } else {
          _playOrderCursor = 0;
        }
      } else {
        // 到末尾且不循环：自动推进到此停止，手动切歌无操作。
        return;
      }
    } else {
      if (_playOrderCursor - 1 >= 0) {
        _playOrderCursor--;
      } else if (_repeat == RepeatMode.all) {
        _playOrderCursor = _playOrder.length - 1;
      } else {
        return;
      }
    }

    _publish();
    await _loadCurrent(autoplay: true);
  }

  Future<void> _loadCurrent({required bool autoplay}) async {
    final index = _currentIndex;
    if (index < 0) return;
    await _engine.load(_streamUriOf(_queue[index].id));
    if (autoplay) await _engine.play();
  }

  void _publish() {
    _state = PlaybackQueueState(
      queue: _queue,
      currentIndex: _currentIndex,
      repeatMode: _repeat,
      shuffle: _shuffle,
    );
    _states.add(_state);
  }
}

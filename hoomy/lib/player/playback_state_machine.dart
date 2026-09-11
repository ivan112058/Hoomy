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
  ///
  /// 这是**队列自身**的口径，供系统媒体会话（`audio_service` 的 `queueIndex`）
  /// 使用。随机模式下它与「队列界面里的第几首」不是一回事 —— 界面的播放顺序
  /// 分区走 [PlaybackStateMachine.view]，不要拿这个下标去切界面。
  final int currentIndex;

  final RepeatMode repeatMode;
  final bool shuffle;

  SubsonicSong? get currentSong =>
      currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;
}

/// 队列在**本次播放顺序**下的三段切片（队列覆盖层的分区视图，票据 09）。
///
/// 与 [PlaybackQueueState.queue] + [PlaybackQueueState.currentIndex] 的区别：
/// 后者是「队列本身 + 当前曲目在队列里的下标」，而随机模式下实际的推进顺序
/// （`_playOrder`）与队列自然序不同 —— 用前者分区会把**还没播的歌标成已播放、
/// 把真正下一首放进已播放段**（spec 用户故事 32 要求「知道接下来是什么」）。
/// 因此分区必须按播放顺序取，本视图就是这份顺序的三段切片。
///
/// 三段直接装**曲目**而不是下标：随机模式下「播放顺序里的位置」与「队列下标」
/// 不是一回事，界面拿到下标还要再翻译一次才能显示，容易错位。视图把翻译做完，
/// 界面只管渲染；要跳转就按它在三段里的位置调 [PlaybackStateMachine.jumpTo]。
///
/// - [played]：本轮已经播过的，按播放先后（最早在前）；
/// - [currentSong]：正在播放的那一首；没有当前曲目时为 null；
/// - [upcoming]：接下来要播的，按播放先后。
class QueueView {
  const QueueView({
    required this.played,
    required this.currentSong,
    required this.upcoming,
  });

  /// 空队列的初始视图。
  static const empty = QueueView(
    played: <SubsonicSong>[],
    currentSong: null,
    upcoming: <SubsonicSong>[],
  );

  final List<SubsonicSong> played;
  final SubsonicSong? currentSong;
  final List<SubsonicSong> upcoming;
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

  /// 队列状态在**本次播放顺序**下的分区（队列覆盖层用）。
  ///
  /// 随机模式下它与「队列自然序 + 当前下标」不同，队列界面必须用这一份，
  /// 否则会把真正下一首标成已播放（见 [QueueView]）。
  QueueView get view => QueueView(
    played: [for (var i = 0; i < _playOrderCursor; i++) _queue[_playOrder[i]]],
    currentSong: _currentIndex < 0 ? null : _queue[_currentIndex],
    upcoming: [
      for (var i = _playOrderCursor + 1; i < _playOrder.length; i++)
        _queue[_playOrder[i]],
    ],
  );

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

  /// 跳到**本次播放顺序**里的第 [position] 个，**不更换队列**。
  ///
  /// 队列界面点某一首即跳过去（票据 09）：位置取自 [view]（分区视图给出的
  /// 就是播放顺序里的位置）；队列内容与循环／随机模式都不变，只把当前曲目
  /// 换成那一首，之后仍沿本轮随机顺序继续。与「下一首」一样，这是一次显式的
  /// 曲目切换，`RepeatMode.one` 不拦手动切歌。
  ///
  /// [position] 越界时无操作。
  Future<void> jumpTo(int position) async {
    if (position < 0 || position >= _playOrder.length) return;
    if (position == _playOrderCursor) return;
    _playOrderCursor = position;
    _publish();
    await _loadCurrent(autoplay: true);
  }

  /// 重排「即将播放」段：把当前曲目之后的曲目换成 [newOrder] 给出的顺序。
  ///
  /// [newOrder] 必须是当前 [QueueView.upcoming] 那批曲目的一个排列（按 id 判，
  /// 顺序自由）—— 多一个、少一个、重复或掺进已播放／当前曲目都视为调用方出错，
  /// 整次操作被忽略。
  ///
  /// 已播放段与当前曲目都不动：当前曲目播放不断、索引不变。
  ///
  /// **重排就是排播**：重排后按新队列顺序依次播放，随机模式也照办 —— 随机
  /// 改变的是「以什么次序走过队列」，而拖拽是用户对接下来听什么给出的明确
  /// 顺序（票据 09 的队列覆盖层拖拽），后者优先。因此本轮随机顺序在重排处
  /// 退役：队列被整理成「已播放 + 当前 + 新的即将播放」三段，`shuffle` 开关
  /// 不变。整理是必要的 —— 随机播过的歌散落在队列各处，不收紧的话它们会落进
  /// 新顺序里，把「即将播放」污染成包含已播放的歌。
  void reorderUpcoming(List<SubsonicSong> newOrder) {
    final current = _currentIndex;
    if (current < 0) return;
    final upcoming = view.upcoming;
    if (!_sameSongs(newOrder, upcoming)) return;

    // 位置 → 队列下标：按本轮播放顺序逐位对应。
    final upcomingIndices = [
      for (var i = _playOrderCursor + 1; i < _playOrder.length; i++)
        _playOrder[i],
    ];
    final byId = {
      for (var i = 0; i < upcoming.length; i++) upcoming[i].id: upcomingIndices[i],
    };
    final played = [
      for (final index in _playOrder.take(_playOrderCursor))
        if (index != current) index,
    ];
    _queue = List.unmodifiable([
      for (final index in played) _queue[index],
      _queue[current],
      for (final song in newOrder) _queue[byId[song.id]!],
    ]);
    _playOrder = _naturalOrder();
    _playOrderCursor = played.length;
    _publish();
  }

  /// 清空「即将播放」段：只保留**已经播过**的曲目与当前曲目。
  ///
  /// 当前曲目继续播放，循环／随机模式不变；没有即将播放的曲目时无操作。
  ///
  /// 保留哪些按**本次播放顺序**（`_playOrder`）判定，而不是按队列下标截断 ——
  /// 随机模式下「播过的」不一定是队列里排在前面的那些，按下标截断会留下从未
  /// 播放过的曲目、又丢掉刚播完的。清空后队列被压缩成保留集并重新编号，
  /// 因此队列分区（已播放／当前／即将播放）恢复成连续的三段。
  void clearUpcoming() {
    final current = _currentIndex;
    if (current < 0 || view.upcoming.isEmpty) return;

    final played = [
      for (final index in _playOrder.take(_playOrderCursor))
        if (index != current) index,
    ];
    _queue = List.unmodifiable([
      for (final index in played) _queue[index],
      _queue[current],
    ]);
    // 保留下来的那些仍是队列自然序，本轮随机顺序整体退役。
    _playOrder = _naturalOrder();
    _playOrderCursor = played.length;
    _publish();
  }

  /// [newOrder] 是否是当前「即将播放」那批曲目的一个排列。
  ///
  /// 按 **id** 判：队列里理论上不会出现两首同 id 的歌，id 在这里是曲目身份。
  bool _sameSongs(List<SubsonicSong> newOrder, List<SubsonicSong> upcoming) {
    if (newOrder.length != upcoming.length) return false;
    final expected = {for (final song in upcoming) song.id};
    final seen = <String>{};
    for (final song in newOrder) {
      if (!expected.contains(song.id) || !seen.add(song.id)) return false;
    }
    return true;
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

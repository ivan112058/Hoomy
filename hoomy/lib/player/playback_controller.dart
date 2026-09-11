import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/subsonic/models.dart';
import 'playback_state_machine.dart';
import 'player_engine.dart';
import 'stream_uri.dart';

/// 界面用来判断「播放状态是否换了个人」的标识。
///
/// 队列、当前曲目、播放状态这些**离散**状态一变，它就变；而进度（每 ~200ms）
/// 不影响它。迷你播放条与错误提示条据此只订阅关心的部分，不被进度拖着重建。
class PlaybackSessionIdentity {
  const PlaybackSessionIdentity({required this.songId, required this.playing});

  /// 当前曲目 id；没有当前曲目时为 null。
  final String? songId;

  /// 是否正在播放。
  final bool playing;

  @override
  bool operator ==(Object other) =>
      other is PlaybackSessionIdentity &&
      other.songId == songId &&
      other.playing == playing;

  @override
  int get hashCode => Object.hash(songId, playing);

  @override
  String toString() => 'PlaybackSessionIdentity($songId, playing: $playing)';
}

/// 界面用的播放状态快照：把状态机的队列状态与引擎的播放状态、进度合到一处。
///
/// 界面只读这一个对象，不必分别订阅状态机与引擎的两条流。
class PlaybackSession {
  const PlaybackSession({
    required this.queue,
    required this.engine,
    required this.position,
  });

  final PlaybackQueueState queue;
  final PlayerEngineState engine;

  /// 当前位置；未加载时为 [Duration.zero]。
  final Duration position;

  /// 当前曲目；没有则为 null。
  SubsonicSong? get currentSong => queue.currentSong;

  /// 是否正在播放。
  bool get playing => engine.playing;

  /// 不含进度的状态标识：换歌或播放/暂停变化时与上一帧不等。
  PlaybackSessionIdentity get identity =>
      PlaybackSessionIdentity(songId: currentSong?.id, playing: playing);

  /// 当前曲目总时长：优先用引擎给的（真实解码时长），回退服务端 metadata。
  Duration? get duration => engine.duration ?? _metadataDuration;

  /// 是否已有播放会话（队列非空）。
  bool get hasSession => queue.queue.isNotEmpty;

  Duration? get _metadataDuration {
    final seconds = currentSong?.durationSec;
    return seconds == null ? null : Duration(seconds: seconds);
  }
}

/// 播放接线：把 [PlayerEngine]（真实音频设备）与 [PlaybackStateMachine]
/// （队列规则）接到一起，并向界面暴露一个合并后的状态快照。
///
/// 这是界面触达播放的唯一入口：界面不持有 `just_audio` 的 `Player`，
/// 也不直接驱动状态机。
///
/// 状态经 [notifyListeners] 广播（本类是一个 [ChangeNotifier]），界面用
/// `ListenableBuilder` 订阅。**不要用 `ref.watch(playerControllerProvider)`
/// 期待状态更新重绘** —— provider 的值（本对象）从不变化，Riverpod 因此
/// 不会通知依赖者。
///
/// 只想跟着「当前是哪首」更新的界面（播放列表高亮）用
/// [currentSongIdStream]，避免被每 ~200ms 的进度通知拖着重绘。
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required PlayerEngine engine,
    required StreamUriResolver streamUriOf,
  }) : _engine = engine,
       _machine = PlaybackStateMachine(engine, streamUriOf) {
    _queueSub = _machine.stateStream.listen((state) {
      _queueState = state;
      // 换歌即清掉上一首的失败提示：新曲目的加载有自己的结果。
      _lastError = null;
      _publish();
    });
    _engineStateSub = _engine.stateStream.listen((state) {
      _engineState = state;
      _publish();
    });
    _positionSub = _engine.positionStream.listen((position) {
      _position = position;
      _publish();
    });
    _errorSub = _machine.errorStream.listen((error) {
      _lastError = error;
      _publish();
    });
    // 当前曲目 id：随队列状态变化而发，`distinct` 掉重复（例如只改了循环模式）。
    _songIdSub = _machine.stateStream
        .map((state) => state.currentSong?.id)
        .distinct()
        .listen((id) {
          if (!_songIds.isClosed) _songIds.add(id);
        });
  }

  final PlayerEngine _engine;
  final PlaybackStateMachine _machine;

  final _songIds = StreamController<String?>.broadcast();

  StreamSubscription<PlaybackQueueState>? _queueSub;
  StreamSubscription<PlayerEngineState>? _engineStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerEngineError>? _errorSub;
  StreamSubscription<String?>? _songIdSub;

  PlaybackQueueState _queueState = PlaybackQueueState.empty;
  PlayerEngineState _engineState = PlayerEngineState.idle;
  Duration _position = Duration.zero;
  PlayerEngineError? _lastError;

  /// 当前播放状态。
  PlaybackSession get session => PlaybackSession(
    queue: _queueState,
    engine: _engineState,
    position: _position,
  );

  /// 最近一次播放失败；界面用它显示常驻错误提示，关闭后由界面清除。
  PlayerEngineError? get lastError => _lastError;

  /// 当前曲目 id 的变化流；没有当前曲目时为 null。
  ///
  /// 播放列表用它标出正在播的那一行：只在换歌时发，不跟随进度。
  Stream<String?> get currentSongIdStream => _songIds.stream;

  /// 用户已经看到错误提示后清除它。
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    _publish();
  }

  /// 用 [songs] 作为队列并立即从 [startIndex] 开始播放。
  ///
  /// [songs] 是当前曲目所在的上下文（搜索结果／专辑曲目／歌手全部歌曲／
  /// 播放列表曲目），状态机据此连续播放。
  Future<void> playQueue(List<SubsonicSong> songs, {int startIndex = 0}) =>
      _machine.playQueue(songs, startIndex: startIndex);

  /// 开始或继续播放当前曲目。
  Future<void> play() => _machine.play();

  /// 暂停当前曲目。
  Future<void> pause() => _machine.pause();

  /// 播放/暂停切换。
  Future<void> togglePlayPause() =>
      session.playing ? _machine.pause() : _machine.play();

  /// 下一首。
  Future<void> next() => _machine.next();

  /// 上一首。
  Future<void> previous() => _machine.previous();

  /// 跳到本次播放顺序里的第 [position] 个（[view] 里的位置）；越界时无操作。
  Future<void> playAt(int position) => _machine.jumpTo(position);

  /// 重排「即将播放」段：[newOrder] 必须是 [QueueView.upcoming] 那批曲目的一个
  /// 排列，否则整次操作被忽略。
  void reorderUpcoming(List<SubsonicSong> newOrder) =>
      _machine.reorderUpcoming(newOrder);

  /// 是否还有「即将播放」的曲目（队列覆盖层的清空按钮据此启停）。
  bool get hasUpcoming => _machine.view.upcoming.isNotEmpty;

  /// 队列在**本次播放顺序**下的三段分区（队列覆盖层的显示口径）。
  ///
  /// 随机模式下它与「队列自然序 + 当前下标」不同，界面必须用这一份。
  QueueView get view => _machine.view;

  /// 清空「即将播放」段：保留已播放段与当前曲目。
  void clearUpcoming() => _machine.clearUpcoming();

  /// 跳转到 [position]。
  ///
  /// 直达引擎而不经状态机：进度是引擎的能力，状态机只管队列与当前曲目
  /// （票据 05 决策 8）。
  Future<void> seek(Duration position) => _engine.seek(position);

  /// 设置音量（0.0–1.0）。
  ///
  /// 音频会话里的「压低音量」（duck）打断用它，界面不直接碰引擎。
  Future<void> setVolume(double volume) => _engine.setVolume(volume);

  /// 切换循环模式。
  void setRepeatMode(RepeatMode mode) => _machine.setRepeatMode(mode);

  /// 切换随机模式。
  void setShuffle(bool enabled) => _machine.setShuffle(enabled);

  /// 释放引擎与订阅。之后本对象不再可用。
  @override
  Future<void> dispose() async {
    await _queueSub?.cancel();
    await _engineStateSub?.cancel();
    await _positionSub?.cancel();
    await _errorSub?.cancel();
    await _songIdSub?.cancel();
    _queueSub = null;
    _engineStateSub = null;
    _positionSub = null;
    _errorSub = null;
    _songIdSub = null;
    await _songIds.close();
    await _machine.dispose();
    super.dispose();
  }

  void _publish() => notifyListeners();
}

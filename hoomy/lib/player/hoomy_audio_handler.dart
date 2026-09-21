import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/subsonic/models.dart';
import 'playback_controller.dart';
import 'playback_state_machine.dart';
import 'player_engine.dart';
import 'queue_store.dart';
import 'stream_uri.dart';

/// 发布给系统的播放状态签名：只在真正变化时才推。
///
/// 用记录（record）取结构相等，字段增减由编译器盯着，不必人肉维护字符串。
typedef _StateSignature = (
  String? songId,
  bool playing,
  PlayerEngineStatus status,
  RepeatMode repeat,
  bool shuffle,
  int index,
);

/// 系统媒体会话（ADR-0008）：`audio_service` 的 `AudioHandler` 是播放状态的
/// 权威持有者。
///
/// 职责：
/// - **持有播放**：控制器由本 handler 创建并持有（[attach]），界面拿到的就是
///   它持有的这一个，不存在第二份播放状态。
/// - **系统命令入**：接收系统发来的播放命令（Android 媒体通知、TV 遥控器媒体键、
///   锁屏、耳机线控），转发给同一个 [PlaybackController]；应用**不自行分发媒体键**，
///   交给系统经 `MediaSession` 路由（票据 07）。
/// - **状态出**：把控制器的队列、当前曲目与播放状态发布给系统，供媒体通知／
///   Now Playing 卡片／锁屏显示。
///
/// 音频会话（音乐类别、打断、耳机拔出）在 `PlaybackAudioSession` 里，由
/// `playerControllerProvider` 在**引擎构造之后**接线。
class HoomyAudioHandler extends BaseAudioHandler {
  HoomyAudioHandler();

  /// 启动媒体会话；必须在 `runApp` 之前调用（`audio_service` 的要求）。
  static Future<HoomyAudioHandler> init() =>
      AudioService.init<HoomyAudioHandler>(
        builder: HoomyAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.hoomy.channel.audio',
          androidNotificationChannelName: '正在播放',
          androidNotificationChannelDescription: 'Hoomy 的播放控制',
          // 暂停时退出前台服务：Android 12+ 从后台重启前台服务会被系统拒绝，
          // 这是官方推荐的默认做法。
          androidStopForegroundOnPause: true,
        ),
      );

  PlaybackController? _controller;

  /// 封面地址构造器，注册时由 provider 注入（封面属数据层，handler 不碰客户端）。
  Uri Function(String coverArtId)? _coverArtUriOf;

  /// 上一次发布的播放状态签名：只在状态真正变化时推给系统，不跟着每 ~200ms
  /// 的进度通知刷。系统按 `updateTime` 自行外推进度（`PlaybackState.position`）。
  _StateSignature? _lastSignature;

  /// 上一次发布的队列 id：队列不变就不重复推。
  List<String>? _lastQueueIds;

  /// 接管播放：创建并持有控制器，把系统命令与状态发布接到它上面。
  ///
  /// 登录后由 `playerControllerProvider` 调用；退出再登录会换成新控制器，
  /// 这里的监听随之改挂。[queueStore] 传给控制器做队列持久化（票据 11）。
  PlaybackController attach({
    required PlayerEngine engine,
    required StreamUriResolver streamUriOf,
    required Uri Function(String coverArtId) coverArtUriOf,
    QueueStore? queueStore,
  }) {
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: streamUriOf,
      queueStore: queueStore,
    );
    _controller?.removeListener(_broadcast);
    _controller = controller;
    _coverArtUriOf = coverArtUriOf;
    _lastSignature = null;
    _lastQueueIds = null;
    controller.addListener(_broadcast);
    _broadcast();
    return controller;
  }

  /// 解挂 [controller]（退出登录）；不是当前那个则无操作。
  void detach(PlaybackController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_broadcast);
    _controller = null;
    _coverArtUriOf = null;
    _lastSignature = null;
    _lastQueueIds = null;
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(PlaybackState());
  }

  // ---- 系统命令 → 控制器 ----

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> skipToNext() async => _controller?.next();

  @override
  Future<void> skipToPrevious() async => _controller?.previous();

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seek(position);
    // 进度是「时点上的一次跳变」，不改变状态签名，因此显式重推一次。
    _broadcast(force: true);
  }

  @override
  Future<void> stop() async {
    // 系统要求停止：连队列一起清掉，系统和界面都回到「没有可播内容」，
    // 而不是系统显示 idle、界面还留着队列。
    await _controller?.playQueue(const []);
    await super.stop();
  }

  // ---- 控制器状态 → 系统 ----

  void _broadcast({bool force = false}) {
    final controller = _controller;
    if (controller == null) return;
    final snapshot = controller.snapshot;
    final queueState = snapshot.queue;

    final queueIds = [for (final song in queueState.queue) song.id];
    if (!listEquals(queueIds, _lastQueueIds)) {
      _lastQueueIds = queueIds;
      // 队列变化才重推，供系统展示「接下来是什么」。
      queue.add([for (final song in queueState.queue) _toMediaItem(song)]);
    }

    final signature = (
      snapshot.currentSong?.id,
      snapshot.playing,
      snapshot.engine.status,
      queueState.repeatMode,
      queueState.shuffle,
      queueState.currentIndex,
    );
    if (!force && signature == _lastSignature) return;
    _lastSignature = signature;

    final song = snapshot.currentSong;
    mediaItem.add(
      song == null ? null : _toMediaItem(song, duration: snapshot.duration),
    );
    playbackState.add(
      PlaybackState(
        processingState: _processingState(snapshot.engine.status),
        playing: snapshot.playing,
        controls: [
          MediaControl.skipToPrevious,
          if (snapshot.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        updatePosition: snapshot.position,
        bufferedPosition: snapshot.position,
        queueIndex: queueState.currentIndex < 0
            ? null
            : queueState.currentIndex,
        repeatMode: _repeatMode(queueState.repeatMode),
        shuffleMode: queueState.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  MediaItem _toMediaItem(SubsonicSong song, {Duration? duration}) => MediaItem(
    id: song.id,
    title: song.title,
    album: song.album,
    artist: song.artist,
    duration: duration ?? _metadataDuration(song),
    artUri: _artUriOf(song),
  );

  Duration? _metadataDuration(SubsonicSong song) {
    final seconds = song.durationSec;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// 封面地址：通知／锁屏的封面由系统按此地址自行拉取（认证在查询串里）。
  Uri? _artUriOf(SubsonicSong song) {
    final coverArtId = song.coverArtId;
    final build = _coverArtUriOf;
    if (coverArtId == null || coverArtId.isEmpty || build == null) return null;
    return build(coverArtId);
  }

  AudioProcessingState _processingState(PlayerEngineStatus status) =>
      switch (status) {
        PlayerEngineStatus.idle => AudioProcessingState.idle,
        PlayerEngineStatus.loading => AudioProcessingState.loading,
        PlayerEngineStatus.ready => AudioProcessingState.ready,
        PlayerEngineStatus.completed => AudioProcessingState.completed,
      };

  AudioServiceRepeatMode _repeatMode(RepeatMode mode) => switch (mode) {
    RepeatMode.off => AudioServiceRepeatMode.none,
    RepeatMode.all => AudioServiceRepeatMode.all,
    RepeatMode.one => AudioServiceRepeatMode.one,
  };
}

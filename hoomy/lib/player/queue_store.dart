import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/subsonic/models.dart';
import 'playback_state_machine.dart';

/// 播放队列的持久化快照（票据 11）：队列内容、当前曲目下标、播放位置与两种模式。
///
/// 存**完整曲目**而不是只存 id：重建队列时不需要网络往返，离线也能看到
/// 「上次在听什么」。队列本身是公开的音乐元数据，不涉及凭据，因此用
/// `shared_preferences` 这类普通键值存储，不进安全存储。
///
/// **位置的归属是「当前曲目」**：写入方必须保证 [position] 属于
/// `queue[currentIndex]`，否则换歌瞬间会把上一首的位置写进新曲目的快照
/// （由 `PlaybackController` 在换歌时清零位置来保证）。
class QueueSnapshot {
  const QueueSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.repeatMode,
    required this.shuffle,
  });

  /// 从状态机的一份队列状态与播放位置打包成快照。
  ///
  /// 快照与 [PlaybackQueueState] 的字段映射只写在这一处：保存与恢复两侧都
  /// 不再各自拆装，字段增减时编译器会同时盯住两边。
  factory QueueSnapshot.fromState(
    PlaybackQueueState state, {
    required Duration position,
  }) => QueueSnapshot(
    queue: state.queue,
    currentIndex: state.currentIndex,
    position: position,
    repeatMode: state.repeatMode,
    shuffle: state.shuffle,
  );

  /// 队列里的曲目，按队列自然序。
  final List<SubsonicSong> queue;

  /// 当前曲目在 [queue] 中的下标。
  final int currentIndex;

  /// 当前曲目的播放位置。
  final Duration position;

  final RepeatMode repeatMode;
  final bool shuffle;

  /// 快照里的队列与模式部分，直接交给状态机重建。
  PlaybackQueueState get state => PlaybackQueueState(
    queue: queue,
    currentIndex: currentIndex,
    repeatMode: repeatMode,
    shuffle: shuffle,
  );

  Map<String, dynamic> toJson() => {
    'currentIndex': currentIndex,
    'positionMs': position.inMilliseconds,
    'repeatMode': repeatMode.name,
    'shuffle': shuffle,
    'queue': [for (final song in queue) song.toJson()],
  };

  /// 解析持久化 JSON；**任何**字段缺失、类型不符或越界都返回 null。
  ///
  /// 调用方把 null 当作「没有可恢复的队列」——空队列与损坏数据都退化为
  /// 同一件事，不区分也不需要区分（票据 11 的容错要求）。
  static QueueSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;

    final rawQueue = json['queue'];
    if (rawQueue is! List || rawQueue.isEmpty) return null;
    final queue = <SubsonicSong>[];
    for (final item in rawQueue) {
      if (item is! Map) return null;
      try {
        queue.add(SubsonicSong.fromJson(item.cast<String, dynamic>()));
      } catch (_) {
        // 缺 id 或字段类型不符：整份快照作废，不让半截队列进内存。
        return null;
      }
    }

    final currentIndex = _asInt(json['currentIndex']);
    if (currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= queue.length) {
      return null;
    }

    final positionMs = _asInt(json['positionMs']);
    if (positionMs == null) return null;

    final repeatMode = _repeatModeFrom(json['repeatMode']);
    if (repeatMode == null) return null;

    final shuffle = json['shuffle'];
    if (shuffle is! bool) return null;

    return QueueSnapshot(
      queue: queue,
      currentIndex: currentIndex,
      // 负位置收敛到起点：旧数据或时钟回拨不该被当成损坏丢掉整个队列。
      position: positionMs <= 0
          ? Duration.zero
          : Duration(milliseconds: positionMs),
      repeatMode: repeatMode,
      shuffle: shuffle,
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    null => null,
    int i => i,
    _ => null,
  };

  static RepeatMode? _repeatModeFrom(Object? value) {
    for (final mode in RepeatMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

/// 播放队列的落盘读写。
///
/// 只负责「一份快照进、一份快照出」，不含保存时机（那是 `PlaybackController`
/// 的事）。持久化是**尽力而为**：读失败返回 null（当作没存过）、写失败静默
/// 放弃，绝不把异常抛给启动或播放路径 —— 存不下队列只是下次恢复不到，
/// 不该影响这次听歌。
class QueueStore {
  /// 可选注入 [SharedPreferences]（测试用）；缺省时首次读写时惰性获取。
  QueueStore([this._preferences]);

  /// 单服务器单用户（MVP 范围），因此一个固定 key 就够。
  static const key = 'playback_queue';

  SharedPreferences? _preferences;

  /// 惰性取存储；平台不支持或插件缺失时返回 null，由各方法降级为无操作。
  Future<SharedPreferences?> get _prefs async {
    final cached = _preferences;
    if (cached != null) return cached;
    try {
      return _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// 读取上次保存的快照；没存过、数据损坏或存储不可用时为 null。
  Future<QueueSnapshot?> read() async {
    try {
      final raw = (await _prefs)?.getString(key);
      if (raw == null) return null;
      return QueueSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(QueueSnapshot snapshot) async {
    try {
      await (await _prefs)?.setString(key, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // 写不进去只影响下次恢复，本次播放不受影响。
    }
  }

  Future<void> clear() async {
    try {
      await (await _prefs)?.remove(key);
    } catch (_) {
      // 同上：清不掉不是致命错误。
    }
  }
}

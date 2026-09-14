import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/player/playback_state_machine.dart';
import 'package:hoomy/player/queue_store.dart';

/// 票据 11：队列快照的序列化往返与损坏数据容错。
///
/// 这一层不碰播放：只验证「存进去的东西原样读得回来」「读不回来的东西
/// 不把 App 拖崩」。`QueueStore` 走 `shared_preferences` 的内存 mock，
/// 不触达平台通道。
void main() {
  setUp(() {
    // 每个用例从空存储开始，避免用例间互相污染。
    SharedPreferences.setMockInitialValues({});
  });

  /// 一首把 `SubsonicSong` 全部字段都填满的曲目，用于验证序列化不漏字段。
  const fullSong = SubsonicSong(
    id: 'full',
    title: '晴天',
    album: '叶惠美',
    artist: '周杰伦',
    albumId: 'al1',
    artistId: 'ar1',
    track: 3,
    discNumber: 1,
    year: 2003,
    durationSec: 269,
    suffix: 'flac',
    coverArtId: 'mf-full_abc',
    starred: '2026-09-10T00:00:00Z',
  );

  List<SubsonicSong> songs(int count) => [
    for (var i = 0; i < count; i++)
      SubsonicSong(id: 's$i', title: '歌曲 $i', durationSec: 180),
  ];

  group('QueueSnapshot 序列化', () {
    test('往返保留队列、当前索引、位置、循环与随机', () {
      final snapshot = QueueSnapshot(
        queue: [fullSong, ...songs(2)],
        currentIndex: 2,
        position: const Duration(minutes: 3, seconds: 7),
        repeatMode: RepeatMode.all,
        shuffle: true,
      );

      final decoded = QueueSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      );

      expect(decoded, isNotNull);
      expect(decoded!.queue.map((s) => s.id), ['full', 's0', 's1']);
      expect(decoded.currentIndex, 2);
      expect(decoded.position, const Duration(minutes: 3, seconds: 7));
      expect(decoded.repeatMode, RepeatMode.all);
      expect(decoded.shuffle, isTrue);

      // 曲目的每个字段都要回来：重建队列不依赖网络，字段缺一个界面就缺一块。
      final song = decoded.queue.first;
      expect(song.title, fullSong.title);
      expect(song.album, fullSong.album);
      expect(song.artist, fullSong.artist);
      expect(song.albumId, fullSong.albumId);
      expect(song.artistId, fullSong.artistId);
      expect(song.track, fullSong.track);
      expect(song.discNumber, fullSong.discNumber);
      expect(song.year, fullSong.year);
      expect(song.durationSec, fullSong.durationSec);
      expect(song.suffix, fullSong.suffix);
      expect(song.coverArtId, fullSong.coverArtId);
      expect(song.starred, fullSong.starred);
    });

    test('循环三种模式都能往返', () {
      for (final mode in RepeatMode.values) {
        final decoded = QueueSnapshot.fromJson(
          QueueSnapshot(
            queue: songs(1),
            currentIndex: 0,
            position: Duration.zero,
            repeatMode: mode,
            shuffle: false,
          ).toJson(),
        );
        expect(decoded?.repeatMode, mode, reason: '$mode 没有往返回来');
      }
    });

    test('空队列没有可恢复的内容', () {
      final decoded = QueueSnapshot.fromJson(
        QueueSnapshot(
          queue: const [],
          currentIndex: -1,
          position: Duration.zero,
          repeatMode: RepeatMode.off,
          shuffle: false,
        ).toJson(),
      );

      expect(decoded, isNull);
    });

    test('fromState / state 与队列状态一一对应', () {
      final state = PlaybackQueueState(
        queue: songs(3),
        currentIndex: 2,
        repeatMode: RepeatMode.one,
        shuffle: true,
      );

      final snapshot = QueueSnapshot.fromState(
        state,
        position: const Duration(seconds: 7),
      );

      expect(snapshot.queue.map((s) => s.id), ['s0', 's1', 's2']);
      expect(snapshot.currentIndex, 2);
      expect(snapshot.position, const Duration(seconds: 7));
      expect(snapshot.repeatMode, RepeatMode.one);
      expect(snapshot.shuffle, isTrue);

      final restored = snapshot.state;
      expect(restored.queue.map((s) => s.id), state.queue.map((s) => s.id));
      expect(restored.currentIndex, state.currentIndex);
      expect(restored.repeatMode, state.repeatMode);
      expect(restored.shuffle, state.shuffle);
    });
  });

  group('QueueSnapshot 损坏数据', () {
    test('不是 JSON 对象时视为没有数据', () {
      for (final broken in [null, 'x', 42, <dynamic>[], '{"queue":[]}']) {
        expect(QueueSnapshot.fromJson(broken), isNull, reason: '$broken');
      }
    });

    test('队列项缺 id 或类型不符时整份快照作废', () {
      final base = QueueSnapshot(
        queue: songs(2),
        currentIndex: 0,
        position: Duration.zero,
        repeatMode: RepeatMode.off,
        shuffle: false,
      ).toJson();

      Map<String, dynamic> withQueue(Object queue) => {...base, 'queue': queue};

      expect(QueueSnapshot.fromJson(withQueue('nope')), isNull);
      expect(QueueSnapshot.fromJson(withQueue([{'title': '没有 id'}])), isNull);
      expect(QueueSnapshot.fromJson(withQueue([{'id': 5, 'title': 'x'}])), isNull);
    });

    test('当前索引越界或类型不符时整份快照作废', () {
      final base = QueueSnapshot(
        queue: songs(2),
        currentIndex: 0,
        position: Duration.zero,
        repeatMode: RepeatMode.off,
        shuffle: false,
      ).toJson();

      expect(QueueSnapshot.fromJson({...base, 'currentIndex': 5}), isNull);
      expect(QueueSnapshot.fromJson({...base, 'currentIndex': -1}), isNull);
      expect(QueueSnapshot.fromJson({...base, 'currentIndex': '0'}), isNull);
    });

    test('缺位置或随机字段、循环模式不认识时整份快照作废', () {
      final base = QueueSnapshot(
        queue: songs(1),
        currentIndex: 0,
        position: const Duration(seconds: 10),
        repeatMode: RepeatMode.one,
        shuffle: true,
      ).toJson();

      expect(QueueSnapshot.fromJson({...base}..remove('positionMs')), isNull);
      expect(QueueSnapshot.fromJson({...base}..remove('shuffle')), isNull);
      expect(QueueSnapshot.fromJson({...base, 'repeatMode': 'loop'}), isNull);
    });

    test('位置为负数时收敛到起点，不视为损坏', () {
      final base = QueueSnapshot(
        queue: songs(1),
        currentIndex: 0,
        position: const Duration(seconds: 10),
        repeatMode: RepeatMode.off,
        shuffle: false,
      ).toJson();

      final decoded = QueueSnapshot.fromJson({...base, 'positionMs': -500});

      expect(decoded, isNotNull);
      expect(decoded!.position, Duration.zero);
    });
  });

  group('QueueStore', () {
    test('没写过时读到 null', () async {
      expect(await QueueStore().read(), isNull);
    });

    test('写入后读得回同一份快照，清除后回到 null', () async {
      final store = QueueStore();
      final snapshot = QueueSnapshot(
        queue: songs(3),
        currentIndex: 1,
        position: const Duration(seconds: 42),
        repeatMode: RepeatMode.one,
        shuffle: true,
      );

      await store.write(snapshot);
      final restored = await store.read();

      expect(restored, isNotNull);
      expect(restored!.queue.map((s) => s.id), ['s0', 's1', 's2']);
      expect(restored.currentIndex, 1);
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.repeatMode, RepeatMode.one);
      expect(restored.shuffle, isTrue);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('存储里是坏 JSON 文本时读到 null 而不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'playback_queue': '{不是合法 JSON',
      });

      expect(await QueueStore().read(), isNull);
    });
  });
}

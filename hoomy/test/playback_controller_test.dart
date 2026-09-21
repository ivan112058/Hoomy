import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/playback_state_machine.dart';
import 'package:hoomy/player/queue_store.dart';

import 'package:hoomy/player/player_engine.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 06：`PlayerEngine` 之上接出真实播放地址与合并状态。
///
/// 这里仍然不碰音频设备 —— `just_audio` 的 `Player` 是平台插件，单元测试
/// 环境里不存在。用假引擎验证的是**接线**：地址怎么拼、状态怎么合、
/// 错误怎么送到界面。
void main() {
  /// 播放地址来自**会话**（票据 04）：真会话 + 假传输，HTTP 不参与，
  /// `stream` 地址的 `format=raw` 与 `u`/`t`/`s` 认证查询串照旧为生产拼法。
  final session = fakeSession(FakeTransport());
  Uri resolveUri(String id) => session.streamUri(id);

  List<SubsonicSong> songs(int count) => [
    for (var i = 0; i < count; i++)
      SubsonicSong(id: 's$i', title: '歌曲 $i', artist: '歌手', durationSec: 180),
  ];

  ({FakePlayerEngine engine, PlaybackController controller}) build() {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    return (engine: engine, controller: controller);
  }

  group('播放地址（认证与格式）', () {
    test('点歌加载的是 stream 端点、原始格式、认证走查询串', () async {
      final (:engine, :controller) = build();

      await controller.playQueue(songs(1), startIndex: 0);

      final uri = engine.lastLoadedUri!;
      expect(uri.path, '/rest/stream.view');
      // 不转码：请求原始流（ADR-0001）。
      expect(uri.queryParameters['format'], 'raw');
      expect(uri.queryParameters['id'], 's0');
      // 认证走 URL 查询串，不使用请求头（ADR-0010）。
      expect(uri.queryParameters['u'], testCredentials.username);
      expect(uri.queryParameters['t'], isNotEmpty);
      expect(uri.queryParameters['s'], isNotEmpty);

      await controller.dispose();
    });
  });

  group('状态合并', () {
    test('队列、播放状态与进度合成一个快照', () async {
      final (:engine, :controller) = build();

      expect(controller.snapshot.hasQueue, isFalse);
      expect(controller.snapshot.currentSong, isNull);

      await controller.playQueue(songs(3), startIndex: 1);
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
          duration: Duration(seconds: 181),
        ),
      );
      engine.emitPosition(const Duration(seconds: 42));
      await pumpEventQueue();

      final snapshot = controller.snapshot;
      expect(snapshot.hasQueue, isTrue);
      expect(snapshot.currentSong?.id, 's1');
      expect(snapshot.playing, isTrue);
      expect(snapshot.position, const Duration(seconds: 42));
      // 引擎给的时长优先；缺省时回退服务端 metadata（180 秒）。
      expect(snapshot.duration, const Duration(seconds: 181));

      await controller.dispose();
    });

    test('引擎没有时长时回退到曲目 metadata', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(1));

      expect(controller.snapshot.duration, const Duration(seconds: 180));

      await controller.dispose();
    });

    test('播放/暂停切换送给引擎，并反映回快照', () async {
      final (:engine, :controller) = build();
      // 点歌即开始播放：引擎收到一次 play。
      await controller.playQueue(songs(1));
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
        ),
      );
      await pumpEventQueue();
      expect(engine.playCount, 1);
      expect(controller.snapshot.playing, isTrue);

      // 正在播 → 第一次切换是暂停。
      await controller.togglePlayPause();
      expect(engine.pauseCount, 1);
      engine.emitState(
        const PlayerEngineState(
          playing: false,
          status: PlayerEngineStatus.ready,
        ),
      );
      await pumpEventQueue();

      // 已暂停 → 再切换是继续播放。
      await controller.togglePlayPause();
      expect(engine.playCount, 2);

      await controller.dispose();
    });

    test('状态与进度的变化都会通知监听者（界面据此重绘）', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(1));
      var notifications = 0;
      controller.addListener(() => notifications++);

      engine.emitPosition(const Duration(seconds: 5));
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
        ),
      );
      await pumpEventQueue();

      expect(notifications, greaterThanOrEqualTo(2));
      expect(controller.snapshot.position, const Duration(seconds: 5));
      expect(controller.snapshot.playing, isTrue);

      await controller.dispose();
    });
  });

  group('播放失败', () {
    test('引擎报错经状态机转到控制器，界面拿得到可读文案', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(1));

      engine.fail('音频解码失败', detail: '(4) Decoder failed');
      await pumpEventQueue();

      expect(controller.lastError?.message, '音频解码失败');
      expect(controller.lastError?.detail, '(4) Decoder failed');
    });

    test('报错会通知监听者；clearError 清空并再通知一次', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(1));
      var notifications = 0;
      controller.addListener(() => notifications++);

      engine.fail('无法连接到服务器');
      await pumpEventQueue();

      expect(controller.lastError, isNotNull);
      final afterError = notifications;
      expect(afterError, greaterThan(0));

      controller.clearError();
      expect(controller.lastError, isNull);
      expect(notifications, afterError + 1);

      await controller.dispose();
    });

    test('换歌清掉上一首的错误提示', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(2));

      engine.fail('音频解码失败');
      await pumpEventQueue();
      expect(controller.lastError, isNotNull);

      await controller.next();

      expect(controller.lastError, isNull);
      expect(controller.snapshot.currentSong?.id, 's1');

      await controller.dispose();
    });
  });

  group('当前曲目 id 流（列表高亮用）', () {
    test('只在换歌时发，不跟随进度', () async {
      final (:engine, :controller) = build();
      final seen = <String?>[];
      final sub = controller.currentSongIdStream.listen(seen.add);
      await pumpEventQueue();

      await controller.playQueue(songs(3), startIndex: 1);
      await pumpEventQueue();
      // 进度变化不该惊动它。
      engine.emitPosition(const Duration(seconds: 30));
      await pumpEventQueue();
      await controller.next();
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, ['s1', 's2']);

      await controller.dispose();
    });
  });

  group('队列编辑（票据 09 的队列覆盖层）', () {
    test('playAt 跳到队列里的某一首，队列与模式不变', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(4), startIndex: 0);

      await controller.playAt(3);

      expect(controller.snapshot.currentSong?.id, 's3');
      expect(controller.snapshot.queue.queue.map((s) => s.id), [
        's0',
        's1',
        's2',
        's3',
      ]);
      expect(engine.loadedIds, ['s0', 's3']);
      // 换歌清掉上一首的错误提示，与手动切歌一致。
      expect(controller.lastError, isNull);

      await controller.dispose();
    });

    test('reorderUpcoming 改队列顺序且不打断当前曲目', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(4), startIndex: 1);
      final loadsBefore = engine.loadedIds.length;

      // 视图给的是曲目，重排也按曲目给（`[s3, s2]` 倒过来）。
      final upcoming = controller.view.upcoming;
      controller.reorderUpcoming([upcoming.last, upcoming.first]);
      await pumpEventQueue();

      expect(controller.snapshot.queue.queue.map((s) => s.id), [
        's0',
        's1',
        's3',
        's2',
      ]);
      expect(controller.snapshot.currentSong?.id, 's1');
      expect(engine.loadedIds, hasLength(loadsBefore), reason: '重排不重新加载');

      await controller.dispose();
    });

    test('clearUpcoming 清掉当前曲目之后的曲目', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(4), startIndex: 1);

      controller.clearUpcoming();
      await pumpEventQueue();

      expect(controller.snapshot.queue.queue.map((s) => s.id), ['s0', 's1']);
      expect(controller.snapshot.currentSong?.id, 's1');
      expect(controller.snapshot.hasQueue, isTrue);

      await controller.dispose();
    });

    test('队列编辑通知监听者（界面据此重绘分区）', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(4), startIndex: 0);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.reorderUpcoming(controller.view.upcoming.reversed.toList());
      controller.clearUpcoming();
      await pumpEventQueue();

      expect(notifications, 2);

      await controller.dispose();
    });
  });

  group('队列持久化（票据 11）', () {
    setUp(() {
      // 每个用例从空存储开始；`QueueStore` 走内存 mock，不触达平台通道。
      SharedPreferences.setMockInitialValues({});
    });

    ({
      FakePlayerEngine engine,
      PlaybackController controller,
      QueueStore store,
    })
    buildPersistent({Duration interval = const Duration(seconds: 5)}) {
      final engine = FakePlayerEngine();
      final store = QueueStore();
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
        queueStore: store,
        positionSaveInterval: interval,
      );
      return (engine: engine, controller: controller, store: store);
    }

    test('队列变化即自动保存：内容、当前曲目、循环与随机', () async {
      final (:engine, :controller, :store) = buildPersistent();

      await controller.playQueue(songs(3), startIndex: 1);
      await pumpEventQueue();

      var saved = await store.read();
      expect(saved, isNotNull);
      expect(saved!.queue.map((s) => s.id), ['s0', 's1', 's2']);
      expect(saved.currentIndex, 1);
      expect(saved.repeatMode, RepeatMode.off);
      expect(saved.shuffle, isFalse);

      controller.setRepeatMode(RepeatMode.one);
      controller.setShuffle(true);
      await pumpEventQueue();

      saved = await store.read();
      expect(saved!.repeatMode, RepeatMode.one);
      expect(saved.shuffle, isTrue);
      expect(saved.currentIndex, 1);

      await controller.dispose();
    });

    test('换歌时位置归零，不把上一首的位置写进新曲目的快照', () async {
      final (:engine, :controller, :store) = buildPersistent();

      await controller.playQueue(songs(3), startIndex: 0);
      engine.emitPosition(const Duration(seconds: 120));
      await pumpEventQueue();
      await controller.next();
      await pumpEventQueue();

      final saved = await store.read();
      expect(saved!.currentIndex, 1);
      expect(saved.queue[saved.currentIndex].id, 's1');
      expect(saved.position, Duration.zero, reason: '位置属于曲目，换歌后必须从头算');
      // 界面上的位置也回到起点，与快照一致。
      expect(controller.snapshot.position, Duration.zero);

      await controller.dispose();
    });

    test('播放中位置按间隔节流保存，到达间隔才落盘', () async {
      final (:engine, :controller, :store) = buildPersistent(
        interval: const Duration(seconds: 5),
      );
      await controller.playQueue(songs(1));
      await pumpEventQueue();

      engine.emitPosition(const Duration(seconds: 3));
      await pumpEventQueue();
      expect((await store.read())!.position, Duration.zero, reason: '不足间隔不写盘');

      engine.emitPosition(const Duration(seconds: 6));
      await pumpEventQueue();
      expect((await store.read())!.position, const Duration(seconds: 6));

      await controller.dispose();
    });

    test('暂停与 seek 立刻保存当前位置', () async {
      final (:engine, :controller, :store) = buildPersistent(
        interval: const Duration(seconds: 30),
      );
      await controller.playQueue(songs(1));
      engine.emitPosition(const Duration(seconds: 12));
      await pumpEventQueue();

      await controller.pause();
      await pumpEventQueue();
      expect((await store.read())!.position, const Duration(seconds: 12));

      await controller.seek(const Duration(seconds: 90));
      await pumpEventQueue();
      expect((await store.read())!.position, const Duration(seconds: 90));

      await controller.dispose();
    });

    test('清空队列时把存储一起清掉', () async {
      final (:engine, :controller, :store) = buildPersistent();
      await controller.playQueue(songs(2));
      await pumpEventQueue();
      expect(await store.read(), isNotNull);

      await controller.playQueue(const []);
      await pumpEventQueue();

      expect(await store.read(), isNull, reason: '空队列不该留下可恢复的数据');

      await controller.dispose();
    });

    test('启动时按持久化内容重建队列，恢复曲目与位置，且不自动播放', () async {
      final (:engine, :controller, :store) = buildPersistent();
      await store.write(
        QueueSnapshot(
          queue: songs(4),
          currentIndex: 2,
          position: const Duration(seconds: 57),
          repeatMode: RepeatMode.all,
          shuffle: false,
        ),
      );

      await controller.restore();
      await pumpEventQueue();

      final snapshot = controller.snapshot;
      expect(snapshot.hasQueue, isTrue);
      expect(snapshot.queue.queue.map((s) => s.id), ['s0', 's1', 's2', 's3']);
      expect(snapshot.currentSong?.id, 's2');
      expect(snapshot.position, const Duration(seconds: 57));
      expect(snapshot.queue.repeatMode, RepeatMode.all);
      expect(snapshot.playing, isFalse, reason: '恢复后必须停在暂停态');
      expect(engine.loadedIds, ['s2']);
      expect(engine.seeks, [const Duration(seconds: 57)]);
      expect(engine.playCount, 0, reason: '不自动开始播放');

      // 恢复后的第一次播放继续当前曲目，不重新加载。
      await controller.play();
      expect(engine.playCount, 1);
      expect(engine.loadedIds, ['s2']);

      await controller.dispose();
    });

    test('重启往返：新控制器恢复出上次的队列、曲目、位置与模式', () async {
      final first = buildPersistent();
      await first.controller.playQueue(songs(5), startIndex: 1);
      first.controller.setRepeatMode(RepeatMode.one);
      first.controller.setShuffle(true);
      first.engine.emitPosition(const Duration(seconds: 88));
      await pumpEventQueue();
      await first.controller.dispose();

      final second = buildPersistent();
      await second.controller.restore();
      await pumpEventQueue();

      final snapshot = second.controller.snapshot;
      expect(snapshot.queue.queue.map((s) => s.id), ['s0', 's1', 's2', 's3', 's4']);
      expect(snapshot.currentSong?.id, 's1');
      expect(snapshot.position, const Duration(seconds: 88));
      expect(snapshot.queue.repeatMode, RepeatMode.one);
      expect(snapshot.queue.shuffle, isTrue);
      expect(snapshot.playing, isFalse);
      expect(second.engine.playCount, 0);

      await second.controller.dispose();
    });

    test('没有存过或数据损坏时恢复为空队列，不崩溃也不加载', () async {
      final (:engine, :controller, :store) = buildPersistent();

      await controller.restore();
      expect(controller.snapshot.hasQueue, isFalse);

      SharedPreferences.setMockInitialValues({'playback_queue': '{坏数据'});
      final corrupted = buildPersistent();
      await corrupted.controller.restore();
      await pumpEventQueue();

      expect(corrupted.controller.snapshot.hasQueue, isFalse);
      expect(corrupted.controller.snapshot.currentSong, isNull);
      expect(corrupted.engine.loadedIds, isEmpty);
      expect(corrupted.engine.playCount, 0);

      await controller.dispose();
      await corrupted.controller.dispose();
    });

    test('用户已开始播放时，迟到的恢复不覆盖当前会话', () async {
      final (:engine, :controller, :store) = buildPersistent();
      await store.write(
        QueueSnapshot(
          queue: songs(2),
          currentIndex: 0,
          position: const Duration(seconds: 30),
          repeatMode: RepeatMode.off,
          shuffle: false,
        ),
      );

      await controller.playQueue(songs(3), startIndex: 2);
      await controller.restore();
      await pumpEventQueue();

      expect(controller.snapshot.currentSong?.id, 's2');
      expect(controller.snapshot.queue.queue.map((s) => s.id), ['s0', 's1', 's2']);
      expect(engine.loadedIds, ['s2'], reason: '恢复不应再加载另一首');

      await controller.dispose();
    });
  });

  test('dispose 释放引擎与状态机订阅', () async {
    final (:engine, :controller) = build();
    await controller.playQueue(songs(1));

    await controller.dispose();

    expect(engine.disposed, isTrue);
  });
}

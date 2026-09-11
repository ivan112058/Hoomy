import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';
import 'package:hoomy/player/playback_controller.dart';

import 'package:hoomy/player/player_engine.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 06：`PlayerEngine` 之上接出真实播放地址与合并状态。
///
/// 这里仍然不碰音频设备 —— `just_audio` 的 `Player` 是平台插件，单元测试
/// 环境里不存在。用假引擎验证的是**接线**：地址怎么拼、状态怎么合、
/// 错误怎么送到界面。
void main() {
  /// 与生产同源的解析器：真实 `SubsonicClient` 生成 `stream` 地址
  /// （含 `format=raw` 与 `u`/`t`/`s` 认证查询串），Dio 传输不参与。
  final client = SubsonicClient(credentials: testCredentials);
  Uri resolveUri(String id) => client.streamUri(id);

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

      expect(controller.session.hasSession, isFalse);
      expect(controller.session.currentSong, isNull);

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

      final session = controller.session;
      expect(session.hasSession, isTrue);
      expect(session.currentSong?.id, 's1');
      expect(session.playing, isTrue);
      expect(session.position, const Duration(seconds: 42));
      // 引擎给的时长优先；缺省时回退服务端 metadata（180 秒）。
      expect(session.duration, const Duration(seconds: 181));

      await controller.dispose();
    });

    test('引擎没有时长时回退到曲目 metadata', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(1));

      expect(controller.session.duration, const Duration(seconds: 180));

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
      expect(controller.session.playing, isTrue);

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
      expect(controller.session.position, const Duration(seconds: 5));
      expect(controller.session.playing, isTrue);

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
      expect(controller.session.currentSong?.id, 's1');

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

      expect(controller.session.currentSong?.id, 's3');
      expect(controller.session.queue.queue.map((s) => s.id), [
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

      expect(controller.session.queue.queue.map((s) => s.id), [
        's0',
        's1',
        's3',
        's2',
      ]);
      expect(controller.session.currentSong?.id, 's1');
      expect(engine.loadedIds, hasLength(loadsBefore), reason: '重排不重新加载');

      await controller.dispose();
    });

    test('clearUpcoming 清掉当前曲目之后的曲目', () async {
      final (:engine, :controller) = build();
      await controller.playQueue(songs(4), startIndex: 1);

      controller.clearUpcoming();
      await pumpEventQueue();

      expect(controller.session.queue.queue.map((s) => s.id), ['s0', 's1']);
      expect(controller.session.currentSong?.id, 's1');
      expect(controller.session.hasSession, isTrue);

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

  test('dispose 释放引擎与状态机订阅', () async {
    final (:engine, :controller) = build();
    await controller.playQueue(songs(1));

    await controller.dispose();

    expect(engine.disposed, isTrue);
  });
}

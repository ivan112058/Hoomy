import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/player/hoomy_audio_handler.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/playback_state_machine.dart';
import 'package:hoomy/player/player_engine.dart';

import 'fake_player_engine.dart';

/// 票据 07：`AudioHandler` 是播放状态的权威持有者。
///
/// 这里不碰平台：`BaseAudioHandler` 的发布流是纯 Dart。验证三件事 ——
/// 控制器由 handler 创建并持有、系统命令转发到同一个控制器、控制器状态发布给系统。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');
  Uri coverUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/getCoverArt.view?id=$id');

  List<SubsonicSong> songs(int count) => [
    for (var i = 0; i < count; i++)
      SubsonicSong(
        id: 's$i',
        title: '歌曲 $i',
        artist: '歌手 $i',
        album: '专辑',
        durationSec: 180 + i,
        coverArtId: 'cover$i',
      ),
  ];

  ({
    FakePlayerEngine engine,
    PlaybackController controller,
    HoomyAudioHandler handler,
  })
  build() {
    final engine = FakePlayerEngine();
    final handler = HoomyAudioHandler();
    // 控制器由 handler 创建并持有 —— 界面拿到的就是这一个。
    final controller = handler.attach(
      engine: engine,
      streamUriOf: resolveUri,
      coverArtUriOf: coverUri,
    );
    return (engine: engine, controller: controller, handler: handler);
  }

  group('控制器状态 → 系统', () {
    test('当前曲目、队列与封面地址发布给系统媒体会话', () async {
      final (:engine, :controller, :handler) = build();
      await controller.playQueue(songs(3), startIndex: 1);
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
          duration: Duration(seconds: 181),
        ),
      );
      await pumpEventQueue();

      expect(handler.queue.value.map((item) => item.id), ['s0', 's1', 's2']);
      final item = handler.mediaItem.value!;
      expect(item.id, 's1');
      expect(item.title, '歌曲 1');
      expect(item.artist, '歌手 1');
      expect(item.album, '专辑');
      // 引擎给的时长优先。
      expect(item.duration, const Duration(seconds: 181));
      expect(item.artUri?.path, '/rest/getCoverArt.view');
      expect(item.artUri?.queryParameters['id'], 'cover1');

      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.queueIndex, 1);
      expect(state.controls, contains(MediaControl.pause));

      await controller.dispose();
    });

    test('没有当前曲目时清空 mediaItem，状态回到 idle', () async {
      final (:engine, :controller, :handler) = build();
      expect(handler.mediaItem.value, isNull);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );

      await controller.playQueue(songs(1));
      await pumpEventQueue();
      expect(handler.mediaItem.value, isNotNull);

      await controller.dispose();
    });

    test('循环与随机映射到系统的重复／随机模式', () async {
      final (:engine, :controller, :handler) = build();
      await controller.playQueue(songs(2));
      await pumpEventQueue();

      controller.setRepeatMode(RepeatMode.one);
      await pumpEventQueue();
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );

      controller.setRepeatMode(RepeatMode.all);
      await pumpEventQueue();
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.all,
      );

      controller.setShuffle(true);
      await pumpEventQueue();
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.all,
        reason: '随机不改变循环模式',
      );

      await controller.dispose();
    });

    test('进度不作为状态反复推送', () async {
      final (:engine, :controller, :handler) = build();
      await controller.playQueue(songs(1));
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
        ),
      );
      await pumpEventQueue();

      final before = handler.playbackState.value;
      // 纯进度通知不应改变已发布的播放状态签名。
      engine.emitPosition(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(identical(handler.playbackState.value, before), isTrue);

      await controller.dispose();
    });
  });

  group('系统命令 → 控制器', () {
    test('播放／暂停／上一首／下一首／跳转都落到同一个控制器', () async {
      final (:engine, :controller, :handler) = build();
      await controller.playQueue(songs(3), startIndex: 1);
      await pumpEventQueue();

      await handler.pause();
      expect(engine.pauseCount, 1);

      await handler.play();
      expect(engine.playCount, 2);

      await handler.skipToNext();
      expect(controller.session.currentSong?.id, 's2');
      expect(engine.lastLoadedId, 's2');

      await handler.skipToPrevious();
      expect(controller.session.currentSong?.id, 's1');

      await handler.seek(const Duration(seconds: 42));
      expect(engine.seeks.last, const Duration(seconds: 42));

      await controller.dispose();
    });

    test('stop 清空队列、暂停，并把系统状态置为 idle', () async {
      final (:engine, :controller, :handler) = build();
      await controller.playQueue(songs(2));
      await pumpEventQueue();

      await handler.stop();

      expect(engine.pauseCount, 1);
      expect(controller.session.hasSession, isFalse, reason: '停止要连队列一起清掉');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );

      await controller.dispose();
    });
  });

  test('detach 后不再听旧控制器，系统侧回到空态', () async {
    final (:engine, :controller, :handler) = build();
    await controller.playQueue(songs(1));
    await pumpEventQueue();
    expect(handler.mediaItem.value?.id, 's0');

    handler.detach(controller);
    expect(handler.mediaItem.value, isNull);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );

    // 旧控制器继续变化也不再发布。
    await controller.next();
    await pumpEventQueue();
    expect(handler.mediaItem.value, isNull);

    await controller.dispose();
  });

  test('换控制器后旧控制器不再影响系统状态', () async {
    final first = build();
    await first.controller.playQueue(songs(1));
    await pumpEventQueue();
    expect(first.handler.mediaItem.value?.id, 's0');

    // 重新 attach 会换成新控制器（退出再登录的场景）。
    final rebound = first.handler.attach(
      engine: FakePlayerEngine(),
      streamUriOf: resolveUri,
      coverArtUriOf: coverUri,
    );
    await pumpEventQueue();
    // 新控制器还没有队列：系统侧应清空，而不是留着旧曲目。
    expect(first.handler.mediaItem.value, isNull);

    // 旧控制器继续变化也不再影响 handler。
    await first.controller.next();
    await pumpEventQueue();
    expect(first.handler.mediaItem.value, isNull);

    await first.controller.dispose();
    await rebound.dispose();
  });
}

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/player/playback_audio_session.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_engine.dart';

import 'fake_player_engine.dart';

/// 票据 07：音频会话的打断与耳机拔出。
///
/// 会话逻辑只依赖两条事件流（打断、设备变化），注入假流即可脱离设备验证；
/// 生产由 `PlaybackAudioSession.attach` 从全局 `AudioSession` 取真流。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  List<SubsonicSong> songs(int count) => [
    for (var i = 0; i < count; i++) SubsonicSong(id: 's$i', title: '歌曲 $i'),
  ];

  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> becomingNoisy;

  setUp(() {
    interruptions = StreamController<AudioInterruptionEvent>.broadcast();
    becomingNoisy = StreamController<void>.broadcast();
  });

  tearDown(() async {
    await interruptions.close();
    await becomingNoisy.close();
  });

  ({
    FakePlayerEngine engine,
    PlaybackController controller,
    PlaybackAudioSession session,
  })
  build() {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    final session = PlaybackAudioSession(
      controller,
      interruptions: interruptions.stream,
      becomingNoisy: becomingNoisy.stream,
    );
    return (engine: engine, controller: controller, session: session);
  }

  Future<void> playing(FakePlayerEngine engine, PlaybackController controller) async {
    await controller.playQueue(songs(3), startIndex: 0);
    engine.emitState(
      const PlayerEngineState(playing: true, status: PlayerEngineStatus.ready),
    );
    await pumpEventQueue();
  }

  test('pause 型打断：先暂停，打断结束后恢复', () async {
    final (:engine, :controller, :session) = build();
    await playing(engine, controller);
    expect(controller.session.playing, isTrue);

    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await pumpEventQueue();
    expect(engine.pauseCount, 1, reason: '来电／其他应用抢占应暂停');

    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await pumpEventQueue();
    expect(engine.playCount, 2, reason: '打断结束后应恢复播放');

    session.dispose();
    await controller.dispose();
  });

  test('unknown 型打断同样按暂停处理并在结束后恢复', () async {
    final (:engine, :controller, :session) = build();
    await playing(engine, controller);

    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.unknown));
    await pumpEventQueue();
    expect(engine.pauseCount, 1);

    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.unknown));
    await pumpEventQueue();
    expect(engine.playCount, 2);

    session.dispose();
    await controller.dispose();
  });

  test('打断开始时并未在播：结束后不擅自恢复', () async {
    final (:engine, :controller, :session) = build();
    await controller.playQueue(songs(1));
    await controller.pause();
    engine.emitState(
      const PlayerEngineState(playing: false, status: PlayerEngineStatus.ready),
    );
    await pumpEventQueue();
    final playsBefore = engine.playCount;
    final pausesBefore = engine.pauseCount;

    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await pumpEventQueue();
    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await pumpEventQueue();

    expect(engine.pauseCount, pausesBefore);
    expect(engine.playCount, playsBefore, reason: '用户自己的暂停不该被顶掉');

    session.dispose();
    await controller.dispose();
  });

  test('duck 型打断：压低音量、结束后恢复，不暂停', () async {
    final (:engine, :controller, :session) = build();
    await playing(engine, controller);

    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    await pumpEventQueue();
    expect(engine.pauseCount, 0);
    expect(engine.volumes.last, lessThan(1.0));

    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    await pumpEventQueue();
    expect(engine.volumes.last, 1.0);

    session.dispose();
    await controller.dispose();
  });

  test('耳机拔出：暂停且不自动恢复', () async {
    final (:engine, :controller, :session) = build();
    await playing(engine, controller);

    becomingNoisy.add(null);
    await pumpEventQueue();
    expect(engine.pauseCount, 1);

    // 随后的打断结束事件不应把播放顶回来。
    interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
    await pumpEventQueue();
    expect(engine.playCount, 1);

    session.dispose();
    await controller.dispose();
  });

  test('dispose 后不再响应打断与设备事件', () async {
    final (:engine, :controller, :session) = build();
    await playing(engine, controller);
    session.dispose();

    interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
    becomingNoisy.add(null);
    await pumpEventQueue();

    expect(engine.pauseCount, 0);

    await controller.dispose();
  });
}

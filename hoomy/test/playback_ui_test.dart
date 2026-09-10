import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/playback_bar.dart';
import 'package:hoomy/features/player/playback_error_banner.dart';
import 'package:hoomy/features/songs/songs_page.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_engine.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 06 的界面验收：点歌出声后的可见反馈与可控性。
///
/// `just_audio` 的 `Player` 是平台插件，widget 测试里不存在；这里把
/// [playerControllerProvider] 换成一个用 `FakePlayerEngine` 驱动的真实
/// [PlaybackController]，于是「点歌 → 引擎收到什么 → 界面显示什么」
/// 这条链路可以完整断言。
void main() {
  /// 与生产同源的 stream 地址（含 `format=raw` 认证查询串）。
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  List<SubsonicSong> library() => const [
    SubsonicSong(
      id: 's1',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      durationSec: 269,
    ),
    SubsonicSong(
      id: 's2',
      title: '以父之名',
      artist: '周杰伦',
      album: '叶惠美',
      durationSec: 259,
    ),
  ];

  /// 歌曲列表 + 底部播放条，与 [HomeShell] 的形态一致。
  Widget harness(List<Override> overrides) => ProviderScope(
    overrides: [subsonicClientProvider.overrideWithValue(null), ...overrides],
    child: MaterialApp(
      theme: hoomyLightTheme(),
      home: const Scaffold(
        body: SongsPage(),
        // 与 HomeShell 一致：错误提示条在播放条之上，两者都在导航栏之上。
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [PlaybackErrorBanner(), PlaybackBar()],
        ),
      ),
    ),
  );

  /// 固定曲库响应的假传输 → 真实 `SongRepository`。
  SongRepository fakeRepository() {
    final transport = FakeTransport()
      ..ok('search3.view', {
        'searchResult3': {
          'song': [
            for (final song in library())
              {
                'id': song.id,
                'title': song.title,
                'artist': song.artist,
                'album': song.album,
                'duration': song.durationSec,
              },
          ],
        },
      });
    return SongRepository(fakeClient(transport));
  }

  testWidgets('点歌曲列表中的一首即开始播放，界面显示正在播放的曲目', (tester) async {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness([
        songRepositoryProvider.overrideWithValue(fakeRepository()),
        playerControllerProvider.overrideWithValue(controller),
      ]),
    );
    await tester.pumpAndSettle();

    // 未点歌时播放条不占位。
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('以父之名'));
    await tester.pumpAndSettle();

    // 加载的是这首歌、原始格式、认证在查询串里；并且立刻开始播放。
    expect(engine.lastLoadedId, 's2');
    expect(engine.lastLoadedUri?.queryParameters['format'], 'raw');
    expect(engine.playCount, 1);
    // 界面反映当前曲目：标题出现在播放条上（列表里那一条 + 播放条 1 条）。
    expect(find.text('以父之名'), findsNWidgets(2));
    // 播放条带进度条，说明它确实占位了。
    expect(find.byType(Slider), findsOneWidget);

    // 正在播的曲目在列表里用播放态红标出（列表在前，播放条在后），
    // 另一首保持主文字色。
    expect(
      tester.widget<Text>(find.text('以父之名').first).style?.color,
      HoomyColors.playingRed,
    );
    expect(
      tester.widget<Text>(find.text('晴天').first).style?.color,
      isNot(HoomyColors.playingRed),
    );

    // 队列是当前可见的列表：s2 已在末尾且循环关闭，手动「下一首」无操作。
    await tester.tap(find.byTooltip('下一首'));
    await tester.pumpAndSettle();
    expect(engine.lastLoadedId, 's2');

    // 从列表里的第一首开始，才能验证「下一首」真的推进队列。
    await tester.tap(find.text('晴天').first);
    await tester.pumpAndSettle();
    expect(engine.lastLoadedId, 's1');
    await tester.tap(find.byTooltip('下一首'));
    await tester.pumpAndSettle();
    expect(engine.lastLoadedId, 's2');
  });

  testWidgets('播放条可暂停与继续', (tester) async {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness([
        songRepositoryProvider.overrideWithValue(fakeRepository()),
        playerControllerProvider.overrideWithValue(controller),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();

    // 引擎上报「正在播放」后，按钮显示为暂停。
    expect(find.byTooltip('暂停'), findsOneWidget);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    expect(engine.pauseCount, 1);

    engine.emitState(
      const PlayerEngineState(playing: false, status: PlayerEngineStatus.ready),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('播放'), findsOneWidget);
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(engine.playCount, 2);
  });

  testWidgets('进度随播放推进更新，拖进度条能跳转', (tester) async {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness([
        songRepositoryProvider.overrideWithValue(fakeRepository()),
        playerControllerProvider.overrideWithValue(controller),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();

    // 引擎给出真实时长与当前位置，界面按 m:ss 显示。
    engine.emitState(
      const PlayerEngineState(
        playing: true,
        status: PlayerEngineStatus.ready,
        duration: Duration(minutes: 4, seconds: 29),
      ),
    );
    engine.emitPosition(const Duration(minutes: 1, seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('1:05'), findsOneWidget);
    // 4:29 出现两次：列表里《晴天》的时长与播放条的时长。
    expect(find.text('4:29'), findsNWidgets(2));

    // 拖到中段松手 → 引擎收到跳转请求。
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(engine.seeks, hasLength(1));
    expect(engine.seeks.single, greaterThan(const Duration(seconds: 30)));

    // 进度继续推进，界面跟着走。
    engine.emitPosition(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.text('2:00'), findsOneWidget);
  });

  testWidgets('播放失败时界面给出可读提示，可关闭且不静默', (tester) async {
    final engine = FakePlayerEngine();
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness([
        songRepositoryProvider.overrideWithValue(fakeRepository()),
        playerControllerProvider.overrideWithValue(controller),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();

    expect(find.textContaining('播放失败'), findsNothing);

    engine.fail('音频解码失败', detail: '(4) Decoder failed');
    await tester.pumpAndSettle();

    expect(find.textContaining('播放失败：音频解码失败'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.textContaining('播放失败'), findsNothing);

    // 再次失败后换歌，提示自动消失（新曲目的加载有自己的结果）。
    engine.fail('音频解码失败');
    await tester.pumpAndSettle();
    expect(find.textContaining('播放失败'), findsOneWidget);

    await tester.tap(find.byTooltip('下一首'));
    await tester.pumpAndSettle();
    expect(find.textContaining('播放失败'), findsNothing);
  });
}

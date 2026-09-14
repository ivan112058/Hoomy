import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/mini_player_bar.dart';
import 'package:hoomy/features/player/playback_error_banner.dart';
import 'package:hoomy/features/shell/home_shell.dart';
import 'package:hoomy/features/songs/songs_page.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/playback_state_machine.dart' as playback;
import 'package:hoomy/player/player_engine.dart';
import 'package:hoomy/player/player_providers.dart';
import 'package:hoomy/player/queue_store.dart';

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

  /// 歌曲列表 + 迷你播放条，与 [HomeShell] 的形态一致。
  Widget harness(List<Override> overrides) => ProviderScope(
    overrides: [subsonicClientProvider.overrideWithValue(null), ...overrides],
    child: MaterialApp(
      theme: hoomyLightTheme(),
      home: const Scaffold(
        body: SongsPage(),
        // 与 HomeShell 一致：错误提示条在迷你播放条之上，两者都在导航栏之上。
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [PlaybackErrorBanner(), MiniPlayerBar()],
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

  /// 主壳（真实 [HomeShell]）+ 假传输的曲库，用于验证迷你条的挂载位置。
  Widget shell(List<Override> overrides) => ProviderScope(
    overrides: [
      subsonicClientProvider.overrideWithValue(fakeClient(FakeTransport())),
      songRepositoryProvider.overrideWithValue(fakeRepository()),
      ...overrides,
    ],
    child: MaterialApp(theme: hoomyLightTheme(), home: const HomeShell()),
  );

  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(engine: engine, streamUriOf: resolveUri);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('点歌曲列表中的一首即开始播放，界面显示正在播放的曲目', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(
      harness([
        songRepositoryProvider.overrideWithValue(fakeRepository()),
        playerControllerProvider.overrideWithValue(controller),
      ]),
    );
    await tester.pumpAndSettle();

    // 未点歌时迷你播放条不占位。
    expect(find.byType(MiniPlayerBar), findsOneWidget);
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, 0);

    await tester.tap(find.text('以父之名'));
    await tester.pumpAndSettle();

    // 加载的是这首歌、原始格式、认证在查询串里；并且立刻开始播放。
    expect(engine.lastLoadedId, 's2');
    expect(engine.lastLoadedUri?.queryParameters['format'], 'raw');
    expect(engine.playCount, 1);
    // 界面反映当前曲目：标题出现在迷你条上（列表里那一条 + 迷你条 1 条）。
    expect(find.text('以父之名'), findsNWidgets(2));
    // 迷你条占位了，且刻意不带进度条。
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, greaterThan(0));
    expect(find.byType(Slider), findsNothing);

    // 正在播的曲目在列表里用播放态红标出（列表在前，迷你条在后），
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

  testWidgets('迷你条可暂停与继续', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

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

  testWidgets('播放失败时界面给出可读提示，可关闭且不静默', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

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

  testWidgets('迷你条在所有 Tab 页可见', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    await tester.pumpWidget(shell([
      playerControllerProvider.overrideWithValue(controller),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MiniPlayerBar)).height, greaterThan(0));

    // 切到每个 Tab，迷你条都还在，内容仍是当前曲目。
    for (final tab in ['播放列表', '艺术家', '专辑', '歌曲', '更多']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(MiniPlayerBar), matching: find.text('晴天')),
        findsOneWidget,
        reason: '$tab 页看不到迷你条',
      );
    }
  });

  testWidgets('迷你条在窄屏与大字号下不溢出（票据 06 遗留的 TV 底部溢出）', (tester) async {
    final engine = FakePlayerEngine();
    final controller = newController(engine);

    addTearDown(tester.view.reset);
    // 320×480 是仍需支持的最矮屏幕；电视上系统字号会放大到 1.3。
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: shell([playerControllerProvider.overrideWithValue(controller)]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();

    // 错误提示条出现时底部最高：迷你条 + 提示条 + 导航栏仍不得溢出。
    engine.fail('音频解码失败');
    await tester.pumpAndSettle();

    expect(find.textContaining('播放失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重启后经 provider 恢复队列：迷你条显示上次曲目且停在暂停态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = QueueStore();
    await store.write(
      QueueSnapshot(
        queue: library(),
        currentIndex: 1,
        position: const Duration(seconds: 30),
        repeatMode: playback.RepeatMode.all,
        shuffle: false,
      ),
    );
    final engine = FakePlayerEngine();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subsonicClientProvider.overrideWithValue(fakeClient(FakeTransport())),
          songRepositoryProvider.overrideWithValue(fakeRepository()),
          playerEngineProvider.overrideWithValue(engine),
          queueStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(theme: hoomyLightTheme(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 队列与当前曲目来自持久化数据：迷你条直接显示上次在听的那首。
    expect(
      find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.text('以父之名'),
      ),
      findsOneWidget,
    );
    expect(engine.loadedIds, ['s2']);
    expect(engine.seeks, [const Duration(seconds: 30)]);
    expect(engine.playCount, 0, reason: '恢复后停在暂停态，不自动播放');
    expect(find.byTooltip('播放'), findsOneWidget);

    // 用户按下播放：从恢复的位置继续，不重新加载。
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(engine.playCount, 1);
    expect(engine.loadedIds, ['s2']);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/screen/screen_awake.dart';
import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/repositories/lyrics_repository.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/playback_page.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 10 的界面验收：歌词三档呈现、滚动跟随、空态与封面／歌词切换。
///
/// 歌词经真实的 [LyricsRepository]（假传输提供固定响应）取回，因此
/// 「服务端返回什么 → 界面呈现什么档位」是整条链路在验证。
void main() {
  const song1 = SubsonicSong(
    id: 's1',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    durationSec: 269,
  );
  const song2 = SubsonicSong(
    id: 's2',
    title: '以父之名',
    artist: '周杰伦',
    album: '叶惠美',
    durationSec: 259,
  );

  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Widget harness(
    PlaybackController controller,
    FakeTransport transport, {
    ScreenAwake? screenAwake,
  }) {
    final client = fakeClient(transport);
    return ProviderScope(
      overrides: [
        playerControllerProvider.overrideWithValue(controller),
        lyricsRepositoryProvider.overrideWithValue(LyricsRepository(client)),
        if (screenAwake != null)
          screenAwakeProvider.overrideWithValue(screenAwake),
      ],
      child: MaterialApp(
        theme: hoomyLightTheme(),
        home: PlaybackPage(controller: controller),
      ),
    );
  }

  /// 注册一条固定结构化歌词响应。
  FakeTransport structuredLyrics(
    List<Map<String, Object?>> lines, {
    bool synced = true,
    List<Map<String, Object?>> cueLines = const [],
  }) => FakeTransport()
    ..ok('getLyricsBySongId.view', {
      'lyricsList': {
        'structuredLyrics': [
          {
            'synced': synced,
            'line': lines,
            if (cueLines.isNotEmpty) 'cueLine': cueLines,
          },
        ],
      },
    });

  /// 让异步的歌词取数跑完。
  ///
  /// `pumpAndSettle` 在没有待调度帧时就停了，而取数的 Future 完成前不一定会有
  /// 帧被调度；多推一次带时长的 pump 让它落地。
  Future<void> settleAsync(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  /// 打开播放页，等歌词预取完成，再从封面切到歌词。
  Future<void> openLyrics(
    WidgetTester tester,
    PlaybackController controller,
  ) async {
    await controller.playQueue(const [song1, song2], startIndex: 0);
    await settleAsync(tester);
    await tester.tap(find.byType(CoverArt));
    await tester.pumpAndSettle();
  }

  List<TextSpan> spansOf(WidgetTester tester, String line) {
    final text = tester.widget<Text>(find.text(line));
    return (text.textSpan! as TextSpan).children!.cast<TextSpan>();
  }

  group('封面与歌词同层切换', () {
    testWidgets('点封面切到歌词，点歌词切回封面', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        {'start': 0, 'value': '第一行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await controller.playQueue(const [song1], startIndex: 0);
      await tester.pumpAndSettle();

      // 初始是封面，没有歌词。
      expect(find.byType(CoverArt), findsOneWidget);
      expect(find.text('第一行'), findsNothing);

      await tester.tap(find.byType(CoverArt));
      await tester.pumpAndSettle();

      expect(find.text('第一行'), findsOneWidget);
      expect(find.byType(CoverArt), findsNothing);

      // 点歌词区域（不是某个按钮）切回封面。
      await tester.tap(find.text('第一行'));
      await tester.pumpAndSettle();

      expect(find.byType(CoverArt), findsOneWidget);
      expect(find.text('第一行'), findsNothing);
    });

    testWidgets('歌词只有一行时，点空白处也能切回封面', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      // 「纯音乐」这类单行歌词：内容比歌词区域小得多。
      final transport = structuredLyrics([
        {'start': 0, 'value': '纯音乐'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);
      expect(find.text('纯音乐'), findsOneWidget);

      // 点歌词区域底部（远离那一行）也应切回封面。
      final area = tester.getRect(find.byType(AnimatedSwitcher));
      await tester.tapAt(Offset(area.center.dx, area.bottom - 8));
      await tester.pumpAndSettle();

      expect(find.byType(CoverArt), findsOneWidget);
      expect(find.text('纯音乐'), findsNothing);
    });

    testWidgets('进入播放页即预取歌词，切换不额外发请求', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        {'start': 0, 'value': '第一行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await controller.playQueue(const [song1], startIndex: 0);
      await settleAsync(tester);

      // 还在封面态，歌词已经取回来了（预取，ADR-0007）。
      expect(transport.requests, hasLength(1));

      await tester.tap(find.byType(CoverArt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一行'));
      await tester.pumpAndSettle();

      expect(transport.requests, hasLength(1), reason: '切换不应重新取歌词');
    });
  });

  group('纯文本档', () {
    testWidgets('静态呈现全部行，不自动滚动', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        {'value': '第一行'},
        {'value': '第二行'},
      ], synced: false);

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      expect(find.text('第一行'), findsOneWidget);
      expect(find.text('第二行'), findsOneWidget);

      final list = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(list.controller!.offset, 0);

      // 位置推进不触发任何滚动（没有时间轴就没有「当前行」）。
      engine.emitPosition(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
    });
  });

  group('逐行档', () {
    testWidgets('当前行高亮并居中自动跟随', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        for (var i = 0; i < 30; i++) {'start': i * 1000, 'value': '第${i + 1}行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      // 位置 0：第一行高亮，其余为次文字色。
      expect(
        tester.widget<Text>(find.text('第1行')).style?.color,
        HoomyColors.lyricHighlightBlue,
      );
      expect(
        tester.widget<Text>(find.text('第2行')).style?.color,
        isNot(HoomyColors.lyricHighlightBlue),
      );

      engine.emitPosition(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      final active = find.text('第11行');
      expect(
        tester.widget<Text>(active).style?.color,
        HoomyColors.lyricHighlightBlue,
      );
      // 当前行落在视口中央（alignment: 0.5）。
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        (tester.getCenter(active).dy - viewport.center.dy).abs(),
        lessThan(10),
        reason: '当前行应居中',
      );
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!
            .offset,
        greaterThan(0),
        reason: '列表应已跟随滚动',
      );
    });

    testWidgets('手动滚动后暂停跟随，超时后恢复', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        for (var i = 0; i < 30; i++) {'start': i * 1000, 'value': '第${i + 1}行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);
      final list = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );

      engine.emitPosition(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(0));

      // 用户手动滚动：跟随暂停。
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      final afterDrag = list.controller!.offset;

      // 位置推进到很靠后的行：因为跟随已暂停，列表不该跳走。
      engine.emitPosition(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, afterDrag, reason: '手动滚动期间不自动跟随');

      // 超时后恢复跟随，并重新对齐当前行（第 26 行）。
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, isNot(afterDrag), reason: '超时后恢复跟随');

      final active = find.text('第26行');
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        (tester.getCenter(active).dy - viewport.center.dy).abs(),
        lessThan(10),
      );
    });

    testWidgets('持续拖动超过恢复时限也不恢复跟随，松手后才计', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        for (var i = 0; i < 30; i++) {'start': i * 1000, 'value': '第${i + 1}行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);
      final list = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      engine.emitPosition(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      // 手指按住持续移动，总时长超过 3s 的恢复时限；每次移动都重置计时。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView)),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(seconds: 1));
      }
      final whileDragging = list.controller!.offset;

      // 拖动还没结束，位置推进不该把列表抢走（否则 ensureVisible 会打断拖动）。
      engine.emitPosition(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, whileDragging);

      // 松手后重新计时，3s 后再恢复跟随。
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final active = find.text('第26行');
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        (tester.getCenter(active).dy - viewport.center.dy).abs(),
        lessThan(10),
      );
    });

    testWidgets('从曲目中段进入歌词态时直接居中当前行', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        for (var i = 0; i < 30; i++) {'start': i * 1000, 'value': '第${i + 1}行'},
      ]);

      await tester.pumpWidget(harness(controller, transport));
      await controller.playQueue(const [song1], startIndex: 0);
      await settleAsync(tester);

      // 还在封面态就把进度推到第 21 行：切到歌词时应直接落在它上面，
      // 而不是停在第一行等下一次进度通知。
      engine.emitPosition(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CoverArt));
      await tester.pumpAndSettle();

      final active = find.text('第21行');
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(
        (tester.getCenter(active).dy - viewport.center.dy).abs(),
        lessThan(10),
        reason: '当前行应直接居中',
      );
    });
  });

  group('逐字档', () {
    testWidgets('当前行已唱部分按 UTF-8 字节区间高亮', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics(
        [
          {'start': 0, 'value': '故事的小黄花'},
        ],
        cueLines: [
          {
            'index': 0,
            'start': 0,
            'end': 2000,
            'value': '故事的小黄花',
            'cue': [
              {
                'start': 0,
                'end': 1000,
                'byteStart': 0,
                'byteEnd': 8,
                'value': '故事的',
              },
              {
                'start': 1000,
                'end': 2000,
                'byteStart': 9,
                'byteEnd': 17,
                'value': '小黄花',
              },
            ],
          },
        ],
      );

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      // 位置 0：只唱到第一个 cue —— 「故事的」高亮、「小黄花」正常。
      var spans = spansOf(tester, '故事的小黄花');
      expect(spans.map((s) => s.text), ['故事的', '小黄花']);
      expect(spans.first.style?.color, HoomyColors.playingRed);

      // 位置推进到第二个 cue：整行都已唱。
      engine.emitPosition(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      spans = spansOf(tester, '故事的小黄花');
      expect(spans.map((s) => s.text), ['故事的小黄花', '']);
      expect(spans.first.style?.color, HoomyColors.playingRed);
    });
  });

  group('无歌词', () {
    testWidgets('显示「暂无歌词」且不可滚动', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      // 结构化与纯文本都没有结果。
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view');

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      expect(find.text('暂无歌词'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(Scrollable), findsNothing);

      // 空态下点**空白处**（不是那行文字）也能切回封面。
      final area = tester.getRect(find.byType(AnimatedSwitcher));
      await tester.tapAt(Offset(area.center.dx, area.bottom - 8));
      await tester.pumpAndSettle();
      expect(find.byType(CoverArt), findsOneWidget);
    });

    testWidgets('结构化无结果时回退纯文本歌词', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view', {
          'lyrics': {'value': '回退的纯文本\n第二行'},
        });

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      expect(find.text('回退的纯文本'), findsOneWidget);
      expect(find.text('第二行'), findsOneWidget);
      expect(find.text('暂无歌词'), findsNothing);
    });

    testWidgets('取歌词失败不伪装成「暂无歌词」', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = FakeTransport()
        ..fail('getLyricsBySongId.view', 40, 'Wrong username or password');

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      // 展示协议层给出的可读原因（与列表页的失败提示同一口径）。
      expect(find.text('Wrong username or password'), findsOneWidget);
      expect(find.text('暂无歌词'), findsNothing);
    });

    testWidgets('失败后点「重试」重新取数并呈现歌词', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = FakeTransport()
        ..fail('getLyricsBySongId.view', 40, 'Wrong username or password');

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);
      expect(find.text('Wrong username or password'), findsOneWidget);

      // 服务端恢复后重试：失败不该被缓存挡住。
      transport.ok('getLyricsBySongId.view', {
        'lyricsList': {
          'structuredLyrics': [
            {
              'synced': true,
              'line': [
                {'start': 0, 'value': '重试成功'},
              ],
            },
          ],
        },
      });
      await tester.tap(find.text('重试'));
      await settleAsync(tester);

      expect(find.text('重试成功'), findsOneWidget);
      expect(find.text('Wrong username or password'), findsNothing);
    });
  });

  group('切歌', () {
    testWidgets('歌词随当前曲目更新，不残留上一首', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = FakeTransport()
        ..responder = (options) {
          final id = options.uri.queryParameters['id'];
          final text = id == 's1' ? '甲歌词' : '乙歌词';
          return jsonResponse({
            'subsonic-response': {
              'status': 'ok',
              'lyricsList': {
                'structuredLyrics': [
                  {
                    'synced': false,
                    'line': [
                      {'value': text},
                    ],
                  },
                ],
              },
            },
          });
        };

      await tester.pumpWidget(harness(controller, transport));
      await openLyrics(tester, controller);

      expect(find.text('甲歌词'), findsOneWidget);

      await controller.next();
      await tester.pumpAndSettle();

      expect(find.text('乙歌词'), findsOneWidget);
      expect(find.text('甲歌词'), findsNothing);
    });
  });

  group('屏幕常亮', () {
    testWidgets('歌词态可开启，离开歌词态即清除', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        {'start': 0, 'value': '第一行'},
      ]);
      final screenAwake = _FakeScreenAwake();

      await tester.pumpWidget(
        harness(controller, transport, screenAwake: screenAwake),
      );
      await controller.playQueue(const [song1], startIndex: 0);
      await tester.pumpAndSettle();

      // 封面态没有常亮开关。
      expect(find.byTooltip('屏幕常亮'), findsNothing);

      await tester.tap(find.byType(CoverArt));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('屏幕常亮'));
      await tester.pumpAndSettle();
      expect(screenAwake.enabled, isTrue);
      expect(find.byTooltip('关闭屏幕常亮'), findsOneWidget);

      // 切回封面：常亮清除。
      await tester.tap(find.text('第一行'));
      await tester.pumpAndSettle();
      expect(screenAwake.enabled, isFalse);
    });

    testWidgets('开着常亮离开播放页也会清除', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = structuredLyrics([
        {'start': 0, 'value': '第一行'},
      ]);
      final screenAwake = _FakeScreenAwake();

      await tester.pumpWidget(
        harness(controller, transport, screenAwake: screenAwake),
      );
      await controller.playQueue(const [song1], startIndex: 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CoverArt));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('屏幕常亮'));
      await tester.pumpAndSettle();
      expect(screenAwake.enabled, isTrue);

      // 卸载播放页（相当于离开）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(screenAwake.enabled, isFalse);
    });
  });
}

/// 记录调用的假常亮实现。
class _FakeScreenAwake implements ScreenAwake {
  @override
  bool enabled = false;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }
}

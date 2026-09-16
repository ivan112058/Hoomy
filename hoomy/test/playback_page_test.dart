// Material 里也有一个同名的 RepeatMode（repeating_animation_builder），
// 这里只取本项目的播放循环模式。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/mini_player_bar.dart';
import 'package:hoomy/features/player/playback_controls.dart';
import 'package:hoomy/features/player/playback_page.dart';
import 'package:hoomy/features/player/queue_overlay.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/features/shared/hoomy_icon_button.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/shell/home_shell.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/playback_state_machine.dart';
import 'package:hoomy/player/player_engine.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 09 的界面验收：全屏播放页与队列覆盖层。
///
/// 播放页与队列都只读 [PlaybackController] 的合并快照；这里用
/// [FakePlayerEngine] 驱动一个真实控制器，因此「引擎状态 → 页面显示什么」
/// 与「界面操作 → 控制器收到什么」都能完整断言，不依赖音频设备。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  /// 五首可辨认的曲目，够铺满队列的三个分区。
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
    SubsonicSong(
      id: 's3',
      title: '东风破',
      artist: '周杰伦',
      album: '叶惠美',
      durationSec: 300,
    ),
    SubsonicSong(
      id: 's4',
      title: '梯田',
      artist: '周杰伦',
      album: '叶惠美',
      durationSec: 240,
    ),
  ];

  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// 播放页的测试台：真实 [PlaybackPage] + 注入的控制器。
  ///
  /// 歌词异步值替换成「没有歌词」：本文件的断言对象是播放控件的呈现与交互，
  /// 与歌词取数无关（ADR-0015 测试决策允许在这种用例里替换具体的取数异步值）。
  Widget pageHarness(PlaybackController controller) => ProviderScope(
    overrides: [
      playerControllerProvider.overrideWithValue(controller),
      lyricsProvider.overrideWith((ref, request) => null),
    ],
    child: MaterialApp(
      theme: hoomyLightTheme(),
      home: PlaybackPage(controller: controller),
    ),
  );

  /// 队列覆盖层的测试台。
  Widget queueHarness(PlaybackController controller) => ProviderScope(
    overrides: [playerControllerProvider.overrideWithValue(controller)],
    child: MaterialApp(
      theme: hoomyLightTheme(),
      home: QueueOverlayPage(controller: controller),
    ),
  );

  /// 主壳 + 假传输曲库：验证「点迷你条 → 展开播放页」的接线。
  Widget shellHarness(PlaybackController controller) {
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
    final client = fakeClient(transport);
    return ProviderScope(
      overrides: [
        // 曲库只来自会话（票据 02）；协议客户端仍供播放层与封面使用。
        sessionProvider.overrideWithValue(fakeSession(transport)),
        subsonicClientProvider.overrideWithValue(client),
        playerControllerProvider.overrideWithValue(controller),
      ],
      child: MaterialApp(theme: hoomyLightTheme(), home: const HomeShell()),
    );
  }

  group('播放页', () {
    testWidgets('静止大封面 + 顶栏歌名歌手，且没有唱盘与进度条以外的交互', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await controller.playQueue(library(), startIndex: 0);
      await tester.pumpAndSettle();

      // 封面是静止的方图：只有一个 CoverArt，1:1，且不比屏幕宽。
      final cover = find.byType(CoverArt);
      expect(cover, findsOneWidget);
      final coverSize = tester.getSize(cover);
      expect(coverSize.width, closeTo(coverSize.height, 0.5));
      expect(coverSize.width, greaterThan(200));

      // 顶栏：歌名与歌手，字号按「标题栏」约定（20sp 标题 + 13sp 副标题）。
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      final title = tester.widget<Text>(find.text('晴天'));
      expect(title.style?.fontSize, HoomyDimens.titleFontSize);
      expect(
        tester.getSize(find.byTooltip('收起播放页')).height,
        lessThanOrEqualTo(HoomyDimens.titleBarHeight),
      );
    });

    testWidgets('五键中控：循环、上一首、播放暂停、下一首、随机', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await tester.pumpAndSettle();
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();

      expect(find.byType(PlaybackControls), findsOneWidget);
      expect(find.byTooltip('循环关闭'), findsOneWidget);
      expect(find.byTooltip('上一首'), findsOneWidget);
      expect(find.byTooltip('暂停'), findsOneWidget);
      expect(find.byTooltip('下一首'), findsOneWidget);
      expect(find.byTooltip('随机播放'), findsOneWidget);

      await tester.tap(find.byTooltip('下一首'));
      await tester.pumpAndSettle();
      expect(engine.lastLoadedId, 's3');

      await tester.tap(find.byTooltip('上一首'));
      await tester.pumpAndSettle();
      expect(engine.lastLoadedId, 's2');

      await tester.tap(find.byTooltip('暂停'));
      await tester.pumpAndSettle();
      expect(engine.pauseCount, 1);
      expect(find.byTooltip('播放'), findsOneWidget);
    });

    testWidgets('循环在「关 → 全部 → 单曲」间轮转，图标与随机开关反映状态', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await controller.playQueue(library(), startIndex: 0);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('循环关闭'));
      await tester.pumpAndSettle();
      expect(controller.session.queue.repeatMode, RepeatMode.all);
      expect(find.byTooltip('列表循环'), findsOneWidget);

      await tester.tap(find.byTooltip('列表循环'));
      await tester.pumpAndSettle();
      expect(controller.session.queue.repeatMode, RepeatMode.one);
      expect(find.byTooltip('单曲循环'), findsOneWidget);
      expect(find.byIcon(Icons.repeat_one), findsOneWidget);

      await tester.tap(find.byTooltip('单曲循环'));
      await tester.pumpAndSettle();
      expect(controller.session.queue.repeatMode, RepeatMode.off);
      expect(find.byTooltip('循环关闭'), findsOneWidget);

      // 随机开关切换的是状态机里的模式。
      await tester.tap(find.byTooltip('随机播放'));
      await tester.pumpAndSettle();
      expect(controller.session.queue.shuffle, isTrue);
      expect(find.byTooltip('关闭随机'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭随机'));
      await tester.pumpAndSettle();
      expect(controller.session.queue.shuffle, isFalse);
    });

    testWidgets('进度条显示当前与剩余时间，拖动松手即跳转', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await tester.pumpAndSettle();
      await controller.playQueue(library(), startIndex: 0);
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
          duration: Duration(seconds: 200),
        ),
      );
      engine.emitPosition(const Duration(seconds: 20));
      await tester.pumpAndSettle();

      expect(find.text('0:20'), findsOneWidget);
      expect(find.text('-3:00'), findsOneWidget);

      // 直接驱动进度条的两个回调：拖动中（onChanged）只改显示，松手
      // （onChangeEnd）才真正跳转。手势与几何由 Flutter 的 Slider 负责，
      // 这里验的是「拖动 → 跳到那个时间」的契约本身。
      // 拖动中（onChanged）只改显示：当前时间跟着手指、剩余时间反过来。
      tester.widget<Slider>(find.byType(Slider)).onChanged!(50);
      await tester.pumpAndSettle();

      expect(engine.seeks, isEmpty, reason: '拖动过程中不发起跳转');
      expect(find.text('0:50'), findsOneWidget);
      expect(find.text('-2:30'), findsOneWidget);

      // 松手（onChangeEnd）才真正跳转一次。
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(50);
      await tester.pumpAndSettle();

      expect(engine.seeks, [const Duration(seconds: 50)]);
      // 松手后回到引擎的真实进度（假引擎不推进，仍是 20 秒）。
      expect(find.text('0:20'), findsOneWidget);
      expect(find.text('-3:00'), findsOneWidget);
    });

    testWidgets('在进度条上拖动即跳转，落到轨道对应位置附近', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await tester.pumpAndSettle();
      await controller.playQueue(library(), startIndex: 0);
      engine.emitState(
        const PlayerEngineState(
          playing: true,
          status: PlayerEngineStatus.ready,
          duration: Duration(seconds: 200),
        ),
      );
      await tester.pumpAndSettle();

      // 从轨道中部按住往左拖：跳转只发生在离手时。
      final track = tester.getRect(find.byType(Slider));
      final gesture = await tester.startGesture(
        Offset(track.center.dx, track.center.dy),
      );
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(Offset(-track.width * 0.05, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(engine.seeks, isEmpty, reason: '拖动过程中不发起跳转');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(engine.seeks, hasLength(1));
      final seek = engine.seeks.single;
      expect(seek, greaterThan(Duration.zero));
      expect(seek, lessThan(const Duration(seconds: 200)));
      expect(
        seek.inSeconds,
        lessThan(100),
        reason: '从中点右侧往左拖过中点，落点应在中点之前',
      );
    });

    testWidgets('时长未知时进度条禁用拖动', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await tester.pumpAndSettle();
      await controller.playQueue(
        const [SubsonicSong(id: 'x', title: '没有时长')],
      );
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });

    testWidgets('进度推进不重建顶栏与中控（只在进度条这一层重绘）', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await controller.playQueue(library(), startIndex: 0);
      await tester.pumpAndSettle();

      // 记录中控里「下一首」按钮所在的 Element；进度通知后必须还是同一个。
      final before = tester.element(find.byTooltip('下一首'));
      engine.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      final after = tester.element(find.byTooltip('下一首'));
      expect(identical(before, after), isTrue);
    });

    testWidgets('没有当前曲目时显示空态，不给点不动的控制', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await tester.pumpAndSettle();

      expect(find.text('暂无播放内容'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(PlaybackControls), findsNothing);
      // 空态仍有顶栏与收起按钮，标题字号与播放态一致。
      expect(
        tester.widget<Text>(find.text('暂无播放内容')).style?.fontSize,
        HoomyDimens.titleFontSize,
      );
      expect(find.byTooltip('收起播放页'), findsOneWidget);
      expect(find.byTooltip('播放队列'), findsNothing);
    });
  });

  group('队列覆盖层', () {
    testWidgets('分区渲染：已播放、正在播放、即将播放，当前曲目有明确标识', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(queueHarness(controller));
      await tester.pumpAndSettle();
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();

      expect(find.text('已播放'), findsOneWidget);
      expect(find.text('正在播放'), findsOneWidget);
      expect(find.text('即将播放'), findsOneWidget);

      // 三段都渲染出各自的曲目（当前曲目同时出现在「正在播放」段）。
      for (final title in ['晴天', '以父之名', '东风破', '梯田']) {
        expect(find.text(title), findsOneWidget, reason: '$title 未出现在队列里');
      }

      // 正在播放的那一行有播放标识（行首的播放图标只在当前行着色）。
      final indicators = tester
          .widgetList<Icon>(find.byIcon(Icons.play_arrow))
          .where((icon) => icon.color == HoomyColors.playingRed);
      expect(indicators, hasLength(1));

      // 按下当前行时标识跟着整行的按压反馈变白，不绕开 HoomyListRow。
      final currentRow = find.ancestor(
        of: find.text('以父之名'),
        matching: find.byType(HoomyListRow),
      );
      final press = await tester.startGesture(tester.getCenter(currentRow));
      await tester.pump(const Duration(milliseconds: 100));
      final pressedIcon = tester
          .widgetList<Icon>(find.byIcon(Icons.play_arrow))
          .where((icon) => icon.color == HoomyColors.pressedForeground);
      expect(pressedIcon, hasLength(1));
      await press.up();
      await tester.pumpAndSettle();

      // 当前行用播放态红标出，已播放与即将播放的行不是。
      expect(
        tester.widget<Text>(find.text('以父之名')).style?.color,
        HoomyColors.playingRed,
      );
      expect(
        tester.widget<Text>(find.text('东风破')).style?.color,
        isNot(HoomyColors.playingRed),
      );
    });

    testWidgets('点队列里的曲目即跳到那一首', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(queueHarness(controller));
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();

      await tester.tap(find.text('梯田'));
      await tester.pumpAndSettle();

      expect(engine.lastLoadedId, 's4');
      expect(controller.session.currentSong?.id, 's4');

      // 已播放段跟着前移：原来的当前曲目进入已播放段。
      expect(controller.view.played.map((s) => s.id), ['s1', 's2', 's3']);
    });

    testWidgets('拖拽「即将播放」段的一行即改变队列顺序', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(queueHarness(controller));
      await controller.playQueue(library(), startIndex: 0);
      await tester.pumpAndSettle();

      expect(controller.session.queue.queue.map((s) => s.id), [
        's1',
        's2',
        's3',
        's4',
      ]);

      // 把「即将播放」的最后一首拖到该段最前（仍然只在即将播放段内）。
      final handle = find.byIcon(Icons.drag_handle).last;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.session.queue.currentSong?.id, 's1');
      expect(controller.session.queue.queue.map((s) => s.id), [
        's1',
        's4',
        's2',
        's3',
      ]);
      expect(engine.loadedIds, ['s1'], reason: '拖拽不重新加载当前曲目');
    });

    testWidgets('一键清空「即将播放」，保留已播放与当前曲目', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(queueHarness(controller));
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();
      expect(find.text('即将播放'), findsOneWidget);

      await tester.tap(find.byTooltip('清空即将播放'));
      await tester.pumpAndSettle();

      expect(find.text('即将播放'), findsNothing);
      expect(controller.session.queue.queue.map((s) => s.id), ['s1', 's2']);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);
      // 清空后按钮不可再按。
      final clear = tester.widget<HoomyIconButton>(
        find.ancestor(
          of: find.byIcon(Icons.clear_all),
          matching: find.byType(HoomyIconButton),
        ),
      );
      expect(clear.onPressed, isNull);
    });

    testWidgets('队列为空时显示空态', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(queueHarness(controller));
      await tester.pumpAndSettle();

      expect(find.text('队列为空'), findsOneWidget);
      expect(find.text('正在播放'), findsNothing);
    });
  });

  group('覆盖层层级', () {
    testWidgets('点迷你条展开播放页，播放页里再展开队列', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(shellHarness(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('晴天'));
      await tester.pumpAndSettle();

      // 点迷你条展开全屏播放页。
      await tester.tap(find.descendant(
        of: find.byType(MiniPlayerBar),
        matching: find.text('晴天'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackPage), findsOneWidget);

      // 播放页里的队列按钮再展开队列覆盖层。
      await tester.tap(find.byTooltip('播放队列'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueOverlayPage), findsOneWidget);
      expect(find.text('播放队列'), findsOneWidget);

      // 收起队列回到播放页，再收起回到主壳。
      await tester.tap(find.byTooltip('收起队列'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueOverlayPage), findsNothing);
      expect(find.byType(PlaybackPage), findsOneWidget);

      await tester.tap(find.byTooltip('收起播放页'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackPage), findsNothing);
      expect(find.byType(MiniPlayerBar), findsOneWidget);
    });

    testWidgets('播放页与队列都不覆写底部迷你条的呈现契约', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(pageHarness(controller));
      await controller.playQueue(library(), startIndex: 0);
      await tester.pumpAndSettle();

      // 播放页有进度条；迷你条刻意没有 —— 两处的约定各自成立。
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(MiniPlayerBar), findsNothing);
    });
  });
}

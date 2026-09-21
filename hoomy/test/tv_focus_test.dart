import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/platform/form_factor.dart';
import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/albums/album_detail_page.dart';
import 'package:hoomy/features/auth/login_page.dart';
import 'package:hoomy/features/player/queue_overlay.dart';
import 'package:hoomy/features/shared/album_grid_cell.dart';
import 'package:hoomy/features/shared/hoomy_icon_button.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/shared/song_tile.dart';
import 'package:hoomy/features/songs/songs_page.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 16 的焦点层验收：D-pad 的方向键移动焦点、确认键触发动作，
/// 聚焦反馈复用按压反馈的视觉（ADR-0013 决策 2）。
///
/// 这里不依赖真实平台：TV 形态由 [HoomyFormFactorScope] 注入，
/// 方向导航模式与 `HoomyApp` 在 TV 上设置的那一份一致。
void main() {
  /// TV 形态的测试台。
  Widget tvHarness(Widget home, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: HoomyFormFactorScope(
          formFactor: HoomyFormFactor.tv,
          child: MaterialApp(
            theme: hoomyLightTheme(),
            builder: (context, child) => MediaQuery(
              // 与 `HoomyApp` 在 TV 上的接线一致：方向键**只**用于移动焦点。
              data: MediaQuery.of(
                context,
              ).copyWith(navigationMode: NavigationMode.directional),
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          ),
        ),
      );

  /// 手机形态的测试台（对照组）。
  Widget phoneHarness(Widget home, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: hoomyLightTheme(), home: home),
      );

  /// 把焦点直接落到某个部件上：D-pad 的遍历顺序不是本文件的断言对象，
  /// 断言的是「聚焦之后发生什么」。
  void focusOn(WidgetTester tester, Finder finder) {
    Focus.of(tester.element(finder)).requestFocus();
  }

  /// 取某部件最近的那块底色。
  Color? boxColorOf(WidgetTester tester, Finder finder) => tester
      .widget<ColoredBox>(
        find.ancestor(of: finder, matching: find.byType(ColoredBox)).first,
      )
      .color;

  group('列表行', () {
    testWidgets('方向键把焦点落到行上：整行铺交互蓝、文字与图标变白', (tester) async {
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: Column(
              children: [
                HoomyListRow(
                  title: '晴天',
                  subtitle: '周杰伦 - 叶惠美',
                  onTap: () {},
                  trailing: (state) => Icon(
                    Icons.star,
                    key: const Key('row-icon'),
                    color: state.active ? Colors.white : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 未聚焦：透明底、主次文字色。
      expect(boxColorOf(tester, find.text('晴天')), Colors.transparent);
      expect(
        tester.widget<Text>(find.text('晴天')).style?.color,
        HoomyColors.lightTextPrimary,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // 聚焦：与按下同一套视觉。
      expect(boxColorOf(tester, find.text('晴天')), HoomyColors.interactionBlue);
      expect(tester.widget<Text>(find.text('晴天')).style?.color, Colors.white);
      expect(
        tester.widget<Text>(find.text('周杰伦 - 叶惠美')).style?.color,
        Colors.white,
      );
      expect(
        tester.widget<Icon>(find.byKey(const Key('row-icon'))).color,
        Colors.white,
      );
    });

    testWidgets('确认键触发行的动作', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: HoomyListRow(title: '晴天', onTap: () => taps++),
          ),
        ),
      );

      focusOn(tester, find.text('晴天'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('右键从行移动到行尾星标', (tester) async {
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: SongTile(
              song: const SubsonicSong(id: 's1', title: '晴天'),
              onTap: () {},
            ),
          ),
        ),
      );

      focusOn(tester, find.text('晴天'));
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.byIcon(Icons.star_border))).hasPrimaryFocus,
        isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        Focus.of(tester.element(find.byIcon(Icons.star_border))).hasPrimaryFocus,
        isTrue,
        reason: 'TV 上必须能从歌曲行聚焦到行尾星标',
      );

      // 左键回到行上：反方向由几何算法命中整行，不必再改判。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('晴天'))).hasPrimaryFocus,
        isTrue,
        reason: '左键应回到行上',
      );
    });

    testWidgets('焦点随方向键移动，长列表里滚入视口', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: ListView.builder(
              controller: controller,
              itemExtent: kHoomyListRowExtent,
              itemCount: 60,
              itemBuilder: (context, i) =>
                  HoomyListRow(title: '歌曲 $i', onTap: () {}),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }

      // 焦点走到列表后段，视口跟着滚动（`Focus` 遍历自带 ensureVisible）。
      expect(controller.offset, greaterThan(0));
      final focused = FocusManager.instance.primaryFocus!;
      expect(focused.context, isNotNull);
    });
  });

  group('图标按钮', () {
    testWidgets('聚焦时整块铺交互蓝、图标变白，确认键触发动作', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: HoomyIconButton(
              icon: Icons.skip_next,
              tooltip: '下一首',
              onPressed: () => presses++,
            ),
          ),
        ),
      );

      expect(boxColorOf(tester, find.byIcon(Icons.skip_next)), Colors.transparent);

      focusOn(tester, find.byIcon(Icons.skip_next));
      await tester.pumpAndSettle();

      expect(
        boxColorOf(tester, find.byIcon(Icons.skip_next)),
        HoomyColors.interactionBlue,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.skip_next)).color,
        Colors.white,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(presses, 1);
    });

    testWidgets('不可点时显示禁用色且不进焦点序列', (tester) async {
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: HoomyIconButton(
              icon: Icons.clear_all,
              tooltip: '清空',
              onPressed: null,
            ),
          ),
        ),
      );

      focusOn(tester, find.byIcon(Icons.clear_all));
      await tester.pumpAndSettle();

      expect(
        boxColorOf(tester, find.byIcon(Icons.clear_all)),
        Colors.transparent,
        reason: '禁用按钮不该拿到焦点',
      );
    });
  });

  group('专辑网格单元', () {
    testWidgets('聚焦时单元铺交互蓝、两行文字变白', (tester) async {
      // 单元按网格算式定尺寸：宽度 100 对应可用宽度 3×100 + 4×间距。
      const cellWidth = 100.0;
      const availableWidth =
          cellWidth * HoomyDimens.albumGridColumns +
          kAlbumGridSpacing * (HoomyDimens.albumGridColumns + 1);
      await tester.pumpWidget(
        tvHarness(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: cellWidth,
                height: albumGridCellExtent(availableWidth),
                child: AlbumGridCell(
                  album: const SubsonicAlbum(
                    id: 'a1',
                    name: '叶惠美',
                    artist: '周杰伦',
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(boxColorOf(tester, find.text('叶惠美')), Colors.transparent);
      expect(
        tester.widget<Text>(find.text('叶惠美')).style?.color,
        HoomyColors.lightTextPrimary,
      );

      focusOn(tester, find.text('叶惠美'));
      await tester.pumpAndSettle();

      expect(boxColorOf(tester, find.text('叶惠美')), HoomyColors.interactionBlue);
      expect(tester.widget<Text>(find.text('叶惠美')).style?.color, Colors.white);
      expect(tester.widget<Text>(find.text('周杰伦')).style?.color, Colors.white);
    });
  });

  group('专辑详情', () {
    FakeTransport albumTransport() => FakeTransport()
      ..ok('getAlbum.view', {
        'album': {
          'id': 'al1',
          'name': '叶惠美',
          'artist': '周杰伦',
          'song': [
            {'id': 's1', 'title': '晴天'},
          ],
        },
      });

    testWidgets('头部星标能被方向键聚焦（从「全部播放」上键过去）', (tester) async {
      await tester.pumpWidget(
        tvHarness(
          const AlbumDetailPage(album: SubsonicAlbum(id: 'al1', name: '叶惠美')),
          overrides: [
            sessionProvider.overrideWithValue(fakeSession(albumTransport())),
          ],
        ),
      );
      await tester.pumpAndSettle();

      focusOn(tester, find.text('全部播放'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // 头部星标排在曲目行的星标之前；用图标定位，才能拿到它所在的 Focus。
      final headerStar = find.byIcon(Icons.star_border).first;
      expect(
        Focus.of(tester.element(headerStar)).hasPrimaryFocus,
        isTrue,
        reason: '专辑详情头部的收藏星标必须能被 D-pad 聚焦',
      );
    });
  });

  group('播放队列', () {
    Uri resolveUri(String id) =>
        Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

    List<SubsonicSong> library() => const [
      SubsonicSong(id: 's1', title: '晴天', artist: '周杰伦', album: '叶惠美'),
      SubsonicSong(id: 's2', title: '以父之名', artist: '周杰伦', album: '叶惠美'),
      SubsonicSong(id: 's3', title: '东风破', artist: '周杰伦', album: '叶惠美'),
      SubsonicSong(id: 's4', title: '梯田', artist: '周杰伦', album: '叶惠美'),
    ];

    PlaybackController newController(FakePlayerEngine engine) {
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('焦点停在行上时左右键调整顺序，并给出可发现提示', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      await tester.pumpWidget(
        tvHarness(
          QueueOverlayPage(controller: controller),
          overrides: [playerControllerProvider.overrideWithValue(controller)],
        ),
      );
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();

      // 可发现性：重排没有可见抓手，靠这一句说明。
      expect(find.text('左右键调整顺序 · 确认键跳播'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle), findsNothing, reason: 'TV 上没有拖拽手柄');

      // 焦点在「梯田」（即将播放的第二首）上按左键：它上移一格。
      focusOn(tester, find.text('梯田'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(controller.session.queue.queue.map((s) => s.id), [
        's1',
        's2',
        's4',
        's3',
      ]);

      // 再按右键退回：左右键是对称的。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.session.queue.queue.map((s) => s.id), [
        's1',
        's2',
        's3',
        's4',
      ]);
    });

    testWidgets('手机形态保留拖拽手柄、不出现左右键提示', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      await tester.pumpWidget(
        phoneHarness(
          QueueOverlayPage(controller: controller),
          overrides: [playerControllerProvider.overrideWithValue(controller)],
        ),
      );
      await controller.playQueue(library(), startIndex: 1);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      expect(find.text('左右键调整顺序 · 确认键跳播'), findsNothing);
    });
  });

  group('登录页', () {
    testWidgets('上下键能在输入框之间移动焦点', (tester) async {
      await tester.pumpWidget(tvHarness(const LoginPage()));

      // 焦点落到服务器地址输入框。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final fields = find.byType(EditableText);
      expect(tester.widget<EditableText>(fields.at(0)).focusNode.hasFocus, isTrue);

      // 再按一次向下：焦点交给用户名 —— 文本框不吞方向键。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(fields.at(1)).focusNode.hasFocus, isTrue);

      // 向上走回服务器地址。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(fields.at(0)).focusNode.hasFocus, isTrue);
    });

    testWidgets('「登录」按钮聚焦时铺交互蓝、文字变白，确认键触发提交', (tester) async {
      await tester.pumpWidget(tvHarness(const LoginPage()));

      Focus.of(tester.element(find.text('登录'))).requestFocus();
      await tester.pumpAndSettle();

      expect(boxColorOf(tester, find.text('登录')), HoomyColors.interactionBlue);
      // 按钮文字色经 DefaultTextStyle 下发，读渲染段落的最终样式。
      expect(
        tester.renderObject<RenderParagraph>(find.text('登录')).text.style?.color,
        Colors.white,
      );

      // 确认键触发提交；三个字段都空，校验先拦下并给出提示。
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('请输入服务器地址'), findsOneWidget);
    });
  });

  group('歌曲页搜索框', () {
    testWidgets('TV 上搜索框可聚焦，向下走到曲目并确认即播放', (tester) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '晴天', 'artist': '周杰伦', 'album': '叶惠美'},
              {'id': 's2', 'title': '以父之名', 'artist': '周杰伦', 'album': '叶惠美'},
            ],
          },
        });
      final engine = FakePlayerEngine();
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: (id) =>
            Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        tvHarness(
          const SongsPage(),
          overrides: [
            // 曲库只来自会话（票据 02）；播放控制器用假引擎驱动。
            sessionProvider.overrideWithValue(fakeSession(transport)),
            playerControllerProvider.overrideWithValue(controller),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 第一次向下：焦点进搜索框（能唤出系统软键盘）。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );

      // 第二次向下：焦点离开搜索框，落到第一首曲目上（整行铺交互蓝）。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isFalse,
      );
      expect(boxColorOf(tester, find.text('晴天')), HoomyColors.interactionBlue);

      // 确认键：从这一首开始播，队列是当前可见列表。
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(engine.lastLoadedId, 's1');
      expect(controller.session.queue.queue.map((s) => s.id), ['s1', 's2']);
    });
  });
}

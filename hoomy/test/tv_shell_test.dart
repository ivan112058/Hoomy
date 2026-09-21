import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/core/alphabet/alphabet.dart';
import 'package:hoomy/core/platform/form_factor.dart';
import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/http/http_transport.dart';
import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/player/mini_player_bar.dart';
import 'package:hoomy/features/player/playback_page.dart';
import 'package:hoomy/features/shared/alphabet_index_bar.dart';
import 'package:hoomy/features/shared/alphabet_sectioned_view.dart';
import 'package:hoomy/features/shared/async_view.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/shell/home_shell.dart';
import 'package:hoomy/features/shell/tv_home_shell.dart';
import 'package:hoomy/main.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 16 的外壳与 TV 形态验收：Android 走侧边导航栏、iOS 走底部 Tab、
/// TV 上隐藏 A–Z 快捷栏、播放页与迷你条可被遥控器操作。
void main() {
  /// 以指定形态包一层，模拟 `HoomyApp` 在 TV 上注入的那份环境。
  ///
  /// 外壳之下会话必不为空（票据 02）：这里注入「真会话 + 假传输」，读端点都有
  /// 空的固定响应，页面因此落在空态而不是错误态。
  Widget harness(Widget home, {HoomyFormFactor formFactor = HoomyFormFactor.tv, FakeTransport? transport, List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(
            fakeSession(transport ?? emptyLibraryTransport()),
          ),
          ...overrides,
        ],
        child: HoomyFormFactorScope(
          formFactor: formFactor,
          child: MaterialApp(
            theme: hoomyLightTheme(),
            builder: (context, child) => MediaQuery(
              data: formFactor == HoomyFormFactor.tv
                  ? MediaQuery.of(
                      context,
                    ).copyWith(navigationMode: NavigationMode.directional)
                  : MediaQuery.of(context),
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          ),
        ),
      );

  /// 借用 `platformFormFactor` 的 debug 覆盖：让整条链（含 Material 默认
  /// 快捷键映射）都按 Android 语义跑，再在用例结束前还原。
  Future<void> asAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  void setLoggedIn() {
    FlutterSecureStorage.setMockInitialValues({
      'navidrome_credentials':
          '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}',
    });
  }

  /// 应用级测试台：凭据在安全存储里，传输是假的 —— 闸口起的会话不发真请求；
  /// 播放引擎置空，widget 测试里不构造平台插件。
  Widget app() => ProviderScope(
        overrides: [
          httpTransportProvider.overrideWithValue(
            fakeDio(FakeTransport()..ok('search3.view')),
          ),
          playerEngineProvider.overrideWithValue(null),
        ],
        child: const HoomyApp(),
      );

  group('根路由按平台分叉外壳', () {
    testWidgets('Android：进入侧边导航外壳，不出现底部 Tab', (tester) async {
      await asAndroid(() async {
        setLoggedIn();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        expect(find.byType(TvHomeShell), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        for (final label in [
          '播放列表',
          '艺术家',
          '专辑',
          '歌曲',
          '风格',
          '我喜欢的歌曲',
          '设置',
        ]) {
          // 「歌曲」既是导航项也是页面标题，因此只要求至少出现一次。
          expect(find.text(label), findsWidgets, reason: '侧边导航缺少 $label');
        }
        expect(find.text('更多'), findsNothing, reason: 'TV 上不再需要「更多」');
      });
    });

    testWidgets('手机（默认宿主平台）：进入底部 Tab 外壳', (tester) async {
      setLoggedIn();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(TvHomeShell), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('侧边导航栏', () {
    testWidgets('启动即聚焦当前项，焦点移动即切换内容区', (tester) async {
      // 给「风格」页一份非空曲库：内容区有可聚焦的行，右键才出得去。
      final transport = emptyLibraryTransport()
        ..ok('getGenres.view', {
          'genres': {
            'genre': [
              {'value': 'Rock', 'songCount': 3},
            ],
          },
        });
      await tester.pumpWidget(harness(const TvHomeShell(), transport: transport));
      await tester.pumpAndSettle();

      // 当前项「歌曲」在启动时就拿到了焦点：整块铺交互蓝。
      // 页面标题也叫「歌曲」，导航栏在树里排在内容区之前，所以取 first。
      final focusedBox = tester.widget<ColoredBox>(
        find.ancestor(of: find.text('歌曲').first, matching: find.byType(ColoredBox)).first,
      );
      expect(focusedBox.color, HoomyColors.interactionBlue);

      // 默认停在第 4 项（歌曲）。
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);

      // **聚焦即切换**：焦点移到「风格」（第 5 项），内容区索引立刻跟着变，
      // 不需要按确认键。
      Focus.of(tester.element(find.text('风格').first)).requestFocus();
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);

      // 内容已经切好了；确认键把焦点送进内容区（不再是「切 Tab」）。
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('风格').first)).hasPrimaryFocus,
        isFalse,
        reason: '确认键应把焦点交给内容区',
      );
    });

    testWidgets('复用既定语 token：导航项字号不另立一套', (tester) async {
      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      // 导航栏里的那一份：页面标题也叫「歌曲」，导航栏在树里排在内容区之前。
      final label = tester.widget<Text>(find.text('歌曲').first);
      expect(label.style?.fontSize, HoomyDimens.listSubtitleFontSize);
    });

    testWidgets('上下键在导航栏首尾循环：首项 ↔ 设置', (tester) async {
      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      /// 某个导航项自身是否拿到主焦点（用它的文字节点找最近的 Focus）。
      bool focused(WidgetTester tester, Finder finder) =>
          Focus.of(tester.element(finder)).hasPrimaryFocus;

      // 首项按上键 → 设置（而不是卡住）。
      Focus.of(tester.element(find.text('播放列表').first)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused(tester, find.text('设置')), isTrue, reason: '首项上键应循环到设置');

      // 设置按下键 → 首项。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        focused(tester, find.text('播放列表').first),
        isTrue,
        reason: '设置下键应循环到首项',
      );

      // 中间项仍走默认几何遍历：歌曲的上键是专辑。
      Focus.of(tester.element(find.text('歌曲').first)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused(tester, find.text('专辑').first), isTrue, reason: '中间项不该被改判');
    });

    testWidgets('设置钉在导航栏最下面，确认键推入设置页', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      // 「设置」排在最后一个一级导航项之下，且 TV 上不再有「更多」。
      expect(
        tester.getTopLeft(find.text('设置')).dy,
        greaterThan(tester.getTopLeft(find.text('我喜欢的歌曲')).dy),
      );
      expect(find.text('更多'), findsNothing);

      // 设置不是页面：焦点停在它上面不该切内容。
      final indexBefore = tester
          .widget<IndexedStack>(find.byType(IndexedStack))
          .index;
      Focus.of(tester.element(find.text('设置'))).requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
        indexBefore,
        reason: '设置不参与「聚焦即切换」',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.text('退出登录'), findsOneWidget, reason: '推入的是设置页');
    });

    testWidgets('软键盘弹出、窗口变矮时导航栏不溢出（可滚动）', (tester) async {
      // 电视上搜索与登录都会唤出系统键盘，`adjustResize` 把窗口压到几百 dp；
      // 导航栏 5 × 76dp 的固定列曾因此溢出 65px（真机发现）。
      tester.view.physicalSize = const Size(960, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      // 溢出会以 FlutterError 让用例失败；这里同时确认导航项都还在。
      for (final label in ['播放列表', '艺术家', '专辑', '歌曲', '风格', '我喜欢的歌曲', '设置']) {
        // 「歌曲」既是导航项也是页面标题。
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('系统返回键回到上一级；TV 上的返回入口是看得清的可聚焦按钮', (tester) async {
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Builder(
              builder: (context) => HoomyListRow(
                title: '专辑详情',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PageScaffold(
                      title: '详情',
                      body: SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Focus.of(tester.element(find.text('专辑详情'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('详情'), findsOneWidget);
      expect(find.byTooltip('返回'), findsOneWidget);

      // 遥控器返回键：系统交给 Navigator，回到上一级列表。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('详情'), findsNothing);
      expect(find.text('专辑详情'), findsOneWidget);
    });
  });

  group('A–Z 快捷栏', () {
    /// 60 条，落在三组、超过快捷栏的显示阈值。
    List<AlphabetSection<String>> sections() => buildAlphabetSections(
      [for (var i = 0; i < 60; i++) '歌曲 $i'],
      keyOf: (title) => title,
    );

    Widget alphabetList() => AlphabetSectionedList<String>(
      sections: sections(),
      itemExtent: kHoomyListRowExtent,
      itemBuilder: (context, title, _) => HoomyDividedRow(
        child: HoomyListRow(title: title),
      ),
    );

    testWidgets('TV 上隐藏（快捷栏是触屏便利，27 个字母逐个做焦点没有可用性）', (tester) async {
      await tester.pumpWidget(harness(Scaffold(body: alphabetList())));
      await tester.pumpAndSettle();

      expect(find.byType(AlphabetIndexBar), findsNothing);
      expect(find.text('歌曲 0'), findsWidgets, reason: '列表本身照常显示');
    });

    testWidgets('手机形态保留', (tester) async {
      await tester.pumpWidget(
        harness(
          Scaffold(body: alphabetList()),
          formFactor: HoomyFormFactor.phone,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlphabetIndexBar), findsOneWidget);
    });
  });

  group('播放页与迷你条的遥控器操作', () {
    Uri resolveUri(String id) =>
        Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

    const songs = [
      SubsonicSong(id: 's1', title: '晴天', artist: '周杰伦', album: '叶惠美'),
      SubsonicSong(id: 's2', title: '以父之名', artist: '周杰伦', album: '叶惠美'),
    ];

    PlaybackController newController(FakePlayerEngine engine) {
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    /// 让异步的歌词预取跑完再断言：`pumpAndSettle` 只看有没有待调度帧，Dio 的
    /// Future 链可能仍留在途，测试结束时会报「Timer is still pending」。
    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }

    testWidgets('播放页：确认键在封面与歌词之间切换', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      await tester.pumpWidget(
        harness(
          PlaybackPage(controller: controller),
          overrides: [playerControllerProvider.overrideWithValue(controller)],
        ),
      );
      await controller.playQueue(songs, startIndex: 0);
      await settle(tester);

      // 封面态：没有歌词。
      expect(find.text('暂无歌词'), findsNothing);

      // 焦点落在封面区（唯一的大块可点区域），确认键切到歌词。
      Focus.of(tester.element(find.byType(CoverArt))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // 服务端没有这首歌的歌词时是明确的空态，而不是空白。
      expect(find.text('暂无歌词'), findsOneWidget);

      // 再按一次确认键切回封面。
      Focus.of(tester.element(find.text('暂无歌词'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('暂无歌词'), findsNothing);
    });

    testWidgets('播放页五键中控：确认键切下一首', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      await tester.pumpWidget(
        harness(
          PlaybackPage(controller: controller),
          overrides: [playerControllerProvider.overrideWithValue(controller)],
        ),
      );
      await controller.playQueue(songs, startIndex: 0);
      await settle(tester);

      Focus.of(tester.element(find.byIcon(Icons.skip_next))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await settle(tester);

      expect(engine.lastLoadedId, 's2');
    });

    testWidgets('迷你播放条：条身聚焦铺交互蓝，确认键触发展开', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      var opened = 0;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: MiniPlayerBar(onTap: () => opened++),
          ),
          overrides: [playerControllerProvider.overrideWithValue(controller)],
        ),
      );
      await controller.playQueue(songs, startIndex: 0);
      await settle(tester);

      Focus.of(tester.element(find.text('晴天'))).requestFocus();
      await tester.pumpAndSettle();

      // 条身聚焦时整块铺交互蓝（与列表行同一套反馈）。
      final body = tester.widget<ColoredBox>(
        find.ancestor(of: find.text('晴天'), matching: find.byType(ColoredBox)).first,
      );
      expect(body.color, HoomyColors.interactionBlue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('外壳的统一兜底（票据 02）', () {
    testWidgets('会话已注入时兜底不出现，页面照常挂载', (tester) async {
      await tester.pumpWidget(harness(const HomeShell()));
      await tester.pumpAndSettle();

      expect(find.text('登录状态异常，请重试'), findsNothing);
      expect(find.byType(IndexedStack), findsOneWidget);
    });

    testWidgets('不变量被破坏（会话未注入）时才出现，且不再挂页面', (tester) async {
      // 刻意绕过登录闸口直接挂外壳：会话无从注入，落到兜底。
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: hoomyLightTheme(), home: const HomeShell()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录状态异常，请重试'), findsOneWidget);
      expect(
        find.byType(IndexedStack),
        findsNothing,
        reason: '不变量破了就不该再挂页面数据',
      );
    });

    testWidgets('TV 外壳同样有一层兜底，且导航 chrome 仍在', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: HoomyFormFactorScope(
            formFactor: HoomyFormFactor.tv,
            child: MaterialApp(
              theme: hoomyLightTheme(),
              home: const TvHomeShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('登录状态异常，请重试'), findsOneWidget);
      // 兜底只替换内容区，一级导航仍然可用。
      expect(find.text('歌曲'), findsOneWidget);
    });
  });
}


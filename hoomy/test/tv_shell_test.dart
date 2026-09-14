import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/alphabet/alphabet.dart';
import 'package:hoomy/core/platform/form_factor.dart';
import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
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

/// 票据 16 的外壳与 TV 形态验收：Android 走侧边导航栏、iOS 走底部 Tab、
/// TV 上隐藏 A–Z 快捷栏、播放页与迷你条可被遥控器操作。
void main() {
  /// 以指定形态包一层，模拟 `HoomyApp` 在 TV 上注入的那份环境。
  Widget harness(Widget home, {HoomyFormFactor formFactor = HoomyFormFactor.tv, List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: [
          subsonicClientProvider.overrideWithValue(null),
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

  group('根路由按平台分叉外壳', () {
    testWidgets('Android：进入侧边导航外壳，不出现底部 Tab', (tester) async {
      await asAndroid(() async {
        setLoggedIn();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [subsonicClientProvider.overrideWithValue(null)],
            child: const HoomyApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TvHomeShell), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        for (final label in ['播放列表', '艺术家', '专辑', '歌曲', '更多']) {
          expect(find.text(label), findsOneWidget, reason: '侧边导航缺少 $label');
        }
      });
    });

    testWidgets('手机（默认宿主平台）：进入底部 Tab 外壳', (tester) async {
      setLoggedIn();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [subsonicClientProvider.overrideWithValue(null)],
          child: const HoomyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(TvHomeShell), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('侧边导航栏', () {
    testWidgets('启动即聚焦当前项，确认键切换内容区', (tester) async {
      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      // 当前项「歌曲」在启动时就拿到了焦点：整块铺交互蓝。
      final focusedBox = tester.widget<ColoredBox>(
        find.ancestor(of: find.text('歌曲'), matching: find.byType(ColoredBox)).first,
      );
      expect(focusedBox.color, HoomyColors.interactionBlue);

      // 默认停在第 4 项（歌曲）。
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);

      // 确认键切到「更多」：内容区索引随之变化。
      Focus.of(tester.element(find.text('更多'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
    });

    testWidgets('复用既定语 token：导航项字号不另立一套', (tester) async {
      await tester.pumpWidget(harness(const TvHomeShell()));
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('歌曲'));
      expect(label.style?.fontSize, HoomyDimens.listSubtitleFontSize);
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
      for (final label in ['播放列表', '艺术家', '专辑', '歌曲', '更多']) {
        expect(find.text(label), findsOneWidget);
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
      await tester.pumpAndSettle();

      // 封面态：没有歌词。
      expect(find.text('暂无歌词'), findsNothing);

      // 焦点落在封面区（唯一的大块可点区域），确认键切到歌词。
      Focus.of(tester.element(find.byType(CoverArt))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // 没有歌词仓库（客户端为 null）时是明确的空态，而不是空白。
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
      await tester.pumpAndSettle();

      Focus.of(tester.element(find.byIcon(Icons.skip_next))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
}

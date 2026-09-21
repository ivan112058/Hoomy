import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/platform/form_factor.dart';
import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/features/shell/home_shell.dart';
import 'package:hoomy/features/shell/tv_home_shell.dart';

import 'fake_transport.dart';

/// 票据 05：切回一个 Tab 时使该 Tab 的取数失效并重取。
///
/// 观察面是**假传输**：改了同一个端点的响应后切走再切回，界面要显示新数据；
/// 「多余重取」用请求条数断言。会话、provider 与失效都是真的，只换掉 HTTP。
void main() {
  /// 曲库（`search3`）的响应 —— 歌曲 Tab 的数据。
  Map<String, Object?> songs(List<String> titles) => {
    'searchResult3': {
      'song': [
        for (var i = 0; i < titles.length; i++)
          {'id': 's$i', 'title': titles[i]},
      ],
    },
  };

  /// 空曲库之上给 `search3` 一份具体响应。
  FakeTransport libraryWith(List<String> titles) =>
      emptyLibraryTransport()..ok('search3.view', songs(titles));

  /// 发往 `search3` 的请求数：歌曲 Tab 有没有真的重取，看它。
  int search3Requests(FakeTransport transport) => transport.requests
      .where((request) => request.uri.pathSegments.last == 'search3.view')
      .length;

  Widget harness(
    Widget home,
    FakeTransport transport, {
    HoomyFormFactor formFactor = HoomyFormFactor.tv,
  }) => ProviderScope(
    overrides: sessionOverrides(transport),
    child: HoomyFormFactorScope(
      formFactor: formFactor,
      child: MaterialApp(
        theme: hoomyLightTheme(),
        // TV 与生产同形：根部把导航模式置为 directional，方向键只用于移动焦点。
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

  /// 导航项本身：导航栏在部件树里排在内容区之前，所以页面标题同名时取 first。
  Finder navItem(String label) => find.text(label).first;

  void focusOn(WidgetTester tester, String label) =>
      Focus.of(tester.element(navItem(label))).requestFocus();

  /// 手机底部 Tab（避开与页面标题同名的那一份）。
  Finder phoneTab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  group('TV：焦点停住才算切回', () {
    testWidgets('切走再切回重取，界面显示新数据', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      expect(find.text('晴天'), findsOneWidget, reason: '冷启动先取到一次');
      final before = search3Requests(transport);

      // 别处（跨设备）改了曲库：同一个端点换成新响应。
      transport.ok('search3.view', songs(['以父之名']));

      // 切走到「专辑」并停住，再到「歌曲」并停住 —— 这才算切回。
      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));
      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(search3Requests(transport), before + 1, reason: '切回应重取一次');
      expect(find.text('以父之名'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
    });

    testWidgets('首次进入的 Tab 不重取：冷启动每页只取一次', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      expect(search3Requests(transport), 1, reason: '冷启动只取一次');

      // 切到从未展示过的「专辑」并停住：首次进入，不该重取。
      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));

      expect(search3Requests(transport), 1, reason: '首次进入不重取');
    });

    testWidgets('焦点落回当前 Tab 上不重取', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();
      final before = search3Requests(transport);

      // 冷启动就停在这个 Tab 上，重新聚焦它不是「切回」。
      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 300));

      expect(search3Requests(transport), before);
    });

    testWidgets('快速扫过导航栏不触发重取', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      // 先让「歌曲」与「专辑」都真正展示过：专辑首次进入（不重取），
      // 再切回歌曲（重取一次）。
      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));
      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final before = search3Requests(transport);

      // 快速扫过：每处都不足 dwell，最后停在从未展示过的「风格」上。
      for (final label in ['艺术家', '专辑', '歌曲', '艺术家', '风格']) {
        focusOn(tester, label);
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(search3Requests(transport), before, reason: '扫过不该打出请求');
    });

    testWidgets('切回「专辑」Tab 重取专辑列表', (tester) async {
      // 不同 Tab 各自失效自己那份取数：这条盯的不是 search3，而是 getAlbumList2。
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      int albumListRequests() => transport.requests
          .where((request) => request.uri.pathSegments.last == 'getAlbumList2.view')
          .length;

      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));
      final afterFirstVisit = albumListRequests();

      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 300));
      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(albumListRequests(), afterFirstVisit + 1, reason: '切回专辑应重取专辑列表');
    });

    testWidgets('焦点没停够时长就离开导航栏（进设置）：不算切回', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      int playlistRequests() => transport.requests
          .where((request) => request.uri.pathSegments.last == 'getPlaylists.view')
          .length;

      // 让「播放列表」与「歌曲」都展示过。
      focusOn(tester, '播放列表');
      await tester.pump(const Duration(milliseconds: 300));
      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // 切回「播放列表」起表，但不到 dwell 就按上键跳去「设置」。
      focusOn(tester, '播放列表');
      await tester.pump(const Duration(milliseconds: 100));
      final before = playlistRequests();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(playlistRequests(), before, reason: '没在导航项上停住就不算切回');
    });

    testWidgets('焦点没停够时长就进内容区：不算切回', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(harness(const TvHomeShell(), transport));
      await tester.pumpAndSettle();

      // 让「专辑」展示过，再切回「歌曲」并起表。
      focusOn(tester, '专辑');
      await tester.pump(const Duration(milliseconds: 300));
      focusOn(tester, '歌曲');
      await tester.pump(const Duration(milliseconds: 100));
      final before = search3Requests(transport);

      // 确认键把焦点送进内容区（曲目行/搜索框），焦点离开导航项。
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(search3Requests(transport), before, reason: '焦点离开导航项就不算停住');
    });
  });

  group('手机：Tab 索引一变就算切回', () {
    testWidgets('切走再切回重取，界面显示新数据', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(
        harness(const HomeShell(), transport, formFactor: HoomyFormFactor.phone),
      );
      await tester.pumpAndSettle();
      expect(find.text('晴天'), findsOneWidget);

      transport.ok('search3.view', songs(['以父之名']));

      await tester.tap(phoneTab('专辑'));
      await tester.pumpAndSettle();
      await tester.tap(phoneTab('歌曲'));
      await tester.pumpAndSettle();

      expect(find.text('以父之名'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
    });

    testWidgets('首次进入的 Tab 不重取，重复点当前 Tab 也不算切回', (tester) async {
      final transport = libraryWith(['晴天']);
      await tester.pumpWidget(
        harness(const HomeShell(), transport, formFactor: HoomyFormFactor.phone),
      );
      await tester.pumpAndSettle();
      final before = search3Requests(transport);

      await tester.tap(phoneTab('专辑'));
      await tester.pumpAndSettle();
      expect(search3Requests(transport), before, reason: '首次进入不重取');

      await tester.tap(phoneTab('专辑'));
      await tester.pumpAndSettle();
      expect(search3Requests(transport), before, reason: '重复点当前 Tab 不算切回');
    });
  });
}

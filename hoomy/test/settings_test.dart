import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/cover/cover_cache.dart';
import 'package:hoomy/data/cover/cover_cache_provider.dart';
import 'package:hoomy/data/credentials/credential_store.dart';
import 'package:hoomy/data/settings/settings_store.dart';
import 'package:hoomy/data/settings/theme_mode_controller.dart';
import 'package:hoomy/features/more/more_page.dart';
import 'package:hoomy/features/settings/settings_page.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/main.dart';

import 'fake_transport.dart';

/// 票据 15 的行为验收：设置页的主题切换、封面缓存占用与清除、退出登录。
///
/// 全部在本机范围内验证：主题存 `shared_preferences` 的内存 mock，缓存写在
/// 临时目录，凭据用安全存储的 mock；「不影响服务端数据」由「退出登录不发任何
/// 请求」与「没有任何写端点」显式断言。
void main() {
  /// 本机凭据的一份固定值（与 `widget_test` 同形）。
  const storedCredentials =
      '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}';

  group('SettingsStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('没设置过主题时为 null，调用方按「跟随系统」处理', () async {
      expect(await SettingsStore().readThemeMode(), isNull);
    });

    test('写入后可读回，新实例读的是同一份存储', () async {
      await SettingsStore().writeThemeMode(ThemeMode.dark);

      expect(await SettingsStore().readThemeMode(), ThemeMode.dark);
    });

    test('值不可识别时按没设置过处理，不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        SettingsStore.themeModeKey: 'midnight',
      });

      expect(await SettingsStore().readThemeMode(), isNull);
    });
  });

  group('ThemeModeController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认跟随系统', () async {
      final container = ProviderContainer.test();

      expect(await container.read(themeModeProvider.future), ThemeMode.system);
    });

    test('启动时读回本机保存的主题', () async {
      SharedPreferences.setMockInitialValues({
        SettingsStore.themeModeKey: 'dark',
      });
      final container = ProviderContainer.test();

      expect(await container.read(themeModeProvider.future), ThemeMode.dark);
    });

    test('切换后立刻生效并落盘', () async {
      final container = ProviderContainer.test();
      await container.read(themeModeProvider.future);

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.light);

      expect(container.read(themeModeProvider).value, ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsStore.themeModeKey), 'light');
    });

    test('存的值损坏时退回跟随系统', () async {
      SharedPreferences.setMockInitialValues({
        SettingsStore.themeModeKey: '???',
      });
      final container = ProviderContainer.test();

      expect(await container.read(themeModeProvider.future), ThemeMode.system);
    });
  });

  group('设置页', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('hoomy_settings_test_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final coverUri = Uri.parse(
      'http://nas.local:4533/rest/getCoverArt.view?id=c1&u=alice',
    );

    /// 页面级测试台：直接挂设置页，省掉整壳的无关取数。
    Widget pageHarness({CoverCache? cache}) {
      return ProviderScope(
        overrides: [
          subsonicClientProvider.overrideWithValue(null),
          if (cache != null) coverCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          theme: hoomyLightTheme(),
          home: const SettingsPage(),
        ),
      );
    }

    /// 整机测试台：真实的 [HoomyApp]（主题接线与登录态路由都在内），
    /// 主题切换与退出登录必须打在它上面，不能打在复制品上。
    Widget appHarness() {
      return ProviderScope(
        overrides: [subsonicClientProvider.overrideWithValue(null)],
        child: const HoomyApp(),
      );
    }

    testWidgets('主题三项可选，默认勾选「跟随系统」', (tester) async {
      await tester.pumpWidget(pageHarness());
      await tester.pumpAndSettle();

      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);

      final selected = find.ancestor(
        of: find.text('跟随系统'),
        matching: find.byType(HoomyListRow),
      );
      expect(
        find.descendant(of: selected, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget, reason: '同时只应有一项被勾选');
    });

    testWidgets('选「深色」后主题立即切换并持久化', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'navidrome_credentials': storedCredentials,
      });

      await tester.pumpWidget(appHarness());
      await tester.pumpAndSettle();
      await _openSettings(tester);

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsStore.themeModeKey), 'dark');

      final selected = find.ancestor(
        of: find.text('深色'),
        matching: find.byType(HoomyListRow),
      );
      expect(
        find.descendant(of: selected, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
    });

    testWidgets('重启后沿用本机保存的主题', (tester) async {
      SharedPreferences.setMockInitialValues({
        SettingsStore.themeModeKey: 'dark',
      });
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(const ProviderScope(child: HoomyApp()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });

    testWidgets('显示封面缓存占用，清除后归零且再次访问会重新下载', (tester) async {
      final requests = <Uri>[];
      final cache = CoverCache(
        directory: dir,
        fetch: (uri) async {
          requests.add(uri);
          return Uint8List(2048);
        },
      );

      // 缓存要读写真实磁盘，而 `testWidgets` 默认在假时钟下运行、真实 IO 不会
      // 完成；因此涉及落盘的操作都放在 `tester.runAsync` 的真实时钟下
      // （同 cover_art_test 的做法）。
      await tester.runAsync(() async {
        // 先缓存一份 2 KB 的封面，设置页应把它算进占用。
        await cache.file('c1', uri: coverUri);
        await tester.pumpWidget(pageHarness(cache: cache));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('当前占用 2.0 KB'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('清除'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('当前占用 0 B'), findsOneWidget);
      expect(find.text('已清除封面缓存'), findsOneWidget);
      expect(await tester.runAsync(cache.totalBytes), 0);

      // 清除后界面再取同一张封面：重新下载，仍拿得到文件（封面照常显示）。
      final file = await tester.runAsync(
        () => cache.file('c1', uri: coverUri),
      );
      expect(file, isNotNull);
      expect(requests, hasLength(2), reason: '清除后同一封面应重新下载');
    });

    testWidgets('没有磁盘缓存时说明原因且「清除」不可点', (tester) async {
      await tester.pumpWidget(pageHarness());
      await tester.pumpAndSettle();

      expect(find.text('无磁盘缓存，封面直接请求服务端'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '清除'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('退出登录需确认；取消则保留凭据与登录态', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'navidrome_credentials': storedCredentials,
      });

      await tester.pumpWidget(appHarness());
      await tester.pumpAndSettle();
      await _openSettings(tester);

      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsOneWidget, reason: '退出登录前必须有确认');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget, reason: '取消后仍留在设置页');
      expect(find.text('连接 Navidrome'), findsNothing);
      expect(await CredentialStore().read(), isNotNull, reason: '取消不得清除凭据');
    });

    testWidgets('确认退出后清除本机凭据并回到登录页', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'navidrome_credentials': storedCredentials,
      });

      await tester.pumpWidget(appHarness());
      await tester.pumpAndSettle();
      await _openSettings(tester);

      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();

      expect(find.text('连接 Navidrome'), findsOneWidget, reason: '应回到登录页');
      expect(find.text('设置'), findsNothing, reason: '设置页必须随登出一并弹掉');
      expect(await CredentialStore().read(), isNull);
    });
  });

  test('退出登录不向服务端发出任何请求（服务端数据不受影响）', () async {
    FlutterSecureStorage.setMockInitialValues({
      'navidrome_credentials':
          '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}',
    });
    final transport = FakeTransport()..ok('ping.view');
    final container = ProviderContainer.test(
      overrides: [subsonicClientProvider.overrideWithValue(fakeClient(transport))],
    );
    // 先让登录态就绪，再退出。
    expect(await container.read(authProvider.future), isNotNull);

    await container.read(authProvider.notifier).logout();

    expect(container.read(authProvider).value, isNull);
    expect(await CredentialStore().read(), isNull);
    expect(transport.requests, isEmpty, reason: '退出登录是本机操作，不碰服务端');
  });

  group('「更多」页设置入口', () {
    testWidgets('左上角设置图标可进入设置页', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [subsonicClientProvider.overrideWithValue(null)],
          child: MaterialApp(
            theme: hoomyLightTheme(),
            home: const MorePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
    });
  });
}

/// 从主壳进入「更多」Tab 再进入设置页。
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
  expect(find.text('设置'), findsOneWidget);
}

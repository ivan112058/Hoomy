import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoomy/core/platform/form_factor.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/http/http_transport.dart';
import 'package:hoomy/data/session/session.dart';
import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/features/auth/login_gate.dart';
import 'package:hoomy/features/songs/songs_page.dart';
import 'package:hoomy/main.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_transport.dart';

/// 登录闸口（票据 02）：唯一表达「有没有会话」的地方。
///
/// 未登录显示登录页；已登录进主界面，并以嵌套作用域注入**非空**会话 ——
/// 会话实例在同一份凭据下稳定（重建不重算、不重取），换了凭据才换实例。
void main() {
  setUp(() {
    // 每个用例从「本机无凭据」开始，避免用例间互相污染。
    FlutterSecureStorage.setMockInitialValues({});
    // 主题模式写在 SharedPreferences 里；不给 mock 时 `getInstance()` 会一直等
    // 平台回复，测试体里的 await 就永远回不来。
    SharedPreferences.setMockInitialValues({});
  });

  void setLoggedIn() {
    FlutterSecureStorage.setMockInitialValues({
      'navidrome_credentials':
          '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}',
    });
  }

  FakeTransport transportWithSong() => FakeTransport()
    ..ok('search3.view', {
      'searchResult3': {
        'song': [
          {'id': 's1', 'title': '晴天', 'artist': '周杰伦'},
        ],
      },
    });

  /// 应用级测试台：整条链路只替换传输这一道接缝，播放引擎置空
  /// （widget 测试里不构造平台插件）。
  Widget app(FakeTransport transport) => ProviderScope(
        overrides: [
          httpTransportProvider.overrideWithValue(fakeDio(transport)),
          playerEngineProvider.overrideWithValue(null),
        ],
        child: const HoomyApp(),
      );

  /// 闸口级测试台：直接把 [LoginGate] 当根部件挂。
  ///
  /// 专门用于「重建」用例：`HoomyApp` 里的 `home: const LoginGate()` 是常量
  /// 实例，父级重建会被 Flutter 直接跳过，验不到闸口自己的重建。
  Widget gateTree(FakeTransport transport) => ProviderScope(
        overrides: [
          httpTransportProvider.overrideWithValue(fakeDio(transport)),
          playerEngineProvider.overrideWithValue(null),
        ],
        child: HoomyFormFactorScope(
          formFactor: HoomyFormFactor.phone,
          child: MaterialApp(home: LoginGate()),
        ),
      );

  /// 闸口之下注入的会话（从页面所在的作用域读，而不是根作用域）。
  Session sessionOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(SongsPage)),
        listen: false,
      ).read(sessionProvider);

  /// 发往 `search3` 的请求数 —— 取数有没有真的重来，看它。
  int search3Requests(FakeTransport transport) => transport.requests
      .where((request) => request.uri.path.endsWith('search3.view'))
      .length;

  testWidgets('未登录时显示登录页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoomyApp()));
    await tester.pumpAndSettle();

    expect(find.text('连接 Navidrome'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('播放列表'), findsNothing);
  });

  testWidgets('已登录时进入主壳并显示五个 Tab', (tester) async {
    setLoggedIn();

    await tester.pumpWidget(app(FakeTransport()..ok('search3.view')));
    await tester.pumpAndSettle();

    expect(find.text('连接 Navidrome'), findsNothing);
    for (final label in ['播放列表', '艺术家', '专辑', '歌曲', '更多']) {
      // 「歌曲」既是导航项也是页面标题，因此只要求至少出现一次。
      expect(find.text(label), findsWidgets, reason: '缺少 Tab: $label');
    }
  });

  testWidgets('闸口注入非空会话：歌曲页跨假传输取到数据', (tester) async {
    setLoggedIn();

    await tester.pumpWidget(app(transportWithSong()));
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsOneWidget);
  });

  testWidgets('同一份凭据下会话实例稳定：闸口重建不重算、不重取', (tester) async {
    setLoggedIn();
    final transport = transportWithSong();

    await tester.pumpWidget(gateTree(transport));
    await tester.pumpAndSettle();

    final before = search3Requests(transport);
    final session = sessionOf(tester);
    expect(before, greaterThan(0), reason: '先确认真的取过一次数');

    // 无关的重建：换一个 LoginGate 实例（同样的 key），build 重新执行。
    await tester.pumpWidget(gateTree(transport));
    await tester.pumpAndSettle();

    expect(sessionOf(tester), same(session), reason: '同一份凭据下必须是同一个会话实例');
    expect(search3Requests(transport), before, reason: '闸口重建不该让页面重新取数');
    expect(find.text('晴天'), findsOneWidget);
  });

  testWidgets('凭据变了就换会话实例：重新登录后重新取数', (tester) async {
    setLoggedIn();
    final transport = transportWithSong()..ok('ping.view');

    await tester.pumpWidget(gateTree(transport));
    await tester.pumpAndSettle();

    final before = search3Requests(transport);
    final session = sessionOf(tester);
    final root = ProviderScope.containerOf(
      tester.element(find.byType(LoginGate)),
      listen: false,
    );

    // 换一份凭据（密码变了，认证 token 也跟着变，必须换协议客户端）。
    // 登录要落盘凭据，走的是平台通道：放在 `runAsync` 的真实时钟下才回得来。
    await tester.runAsync(
      () => root
          .read(authProvider.notifier)
          .login('http://nas.local:4533', 'bob', 'newpass'),
    );
    await tester.pumpAndSettle();

    expect(sessionOf(tester), isNot(same(session)), reason: '换了凭据就得换实例');
    expect(
      search3Requests(transport),
      greaterThan(before),
      reason: '新会话要重新取数',
    );
  });
}

import 'dart:async';

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

import 'fake_player_engine.dart';
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

  /// 闸口级测试台：直接把 [LoginGate] 当根部件挂，会话作用域与生产同形
  /// （在 Navigator 之上，即 `HoomyApp.builder` 的位置）。
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
          child: MaterialApp(
            builder: (context, child) =>
                SessionScope(child: child ?? const SizedBox.shrink()),
            home: const LoginGate(),
          ),
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

  testWidgets('未登录时不构造播放引擎：没有会话就没有可播的内容', (tester) async {
    var engineBuilt = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerEngineProvider.overrideWith((ref) {
            engineBuilt = true;
            return FakePlayerEngine();
          }),
        ],
        child: const HoomyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接 Navidrome'), findsOneWidget);
    expect(engineBuilt, isFalse, reason: '没有会话时不该有人去要播放引擎');
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

  testWidgets('登出是路由事件：压在主界面之上的层级路由被一并清掉', (tester) async {
    setLoggedIn();

    await tester.pumpWidget(app(transportWithSong()));
    await tester.pumpAndSettle();

    // 先取到容器与导航器：层级路由压上去之后，下面的路由会被 Overlay 标记为
    // offstage，`find.byType` 默认跳过它。
    final root = ProviderScope.containerOf(
      tester.element(find.byType(LoginGate)),
      listen: false,
    );
    final navigator = Navigator.of(tester.element(find.byType(SongsPage)));

    // 往主界面之上压一层层级路由（设置页之类的详情页）。
    // 刻意不 await `push`：它的 Future 要等路由被弹出才完成。
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('压在上面的层级页')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('压在上面的层级页'), findsOneWidget);

    // 清凭据即让会话消失；路由自己订阅会话状态，不靠调用点记得弹栈。清凭据要走
    // 平台通道，放在 runAsync 的真实时钟下才回得来。
    await tester.runAsync(() => root.read(authProvider.notifier).logout());
    await tester.pumpAndSettle();

    expect(find.text('压在上面的层级页'), findsNothing, reason: '登出必须重置导航栈');
    expect(find.text('连接 Navidrome'), findsOneWidget, reason: '回到登录页');
  });

  /// 票据 03 的回归：会话作用域必须包住 **Navigator**。
  ///
  /// 闸口 push 出去的详情页在 Overlay 上是 home 路由的兄弟；作用域若只包 home，
  /// 这些页面读 `sessionProvider` 会落到根作用域上抛「会话未注入」。这条用例走
  /// 的还是真 `HoomyApp`（闸口 + 作用域），因此能挡住那类「测试全在根作用域
  /// 注入会话」造成的假绿。
  testWidgets('push 出来的层级页读得到会话，且收藏写也走同一条作用域', (tester) async {
    setLoggedIn();
    final transport = FakeTransport()
      ..ok('search3.view')
      ..ok('star.view')
      ..ok('getAlbumList2.view', {
        'albumList2': {
          'album': [
            {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦'},
          ],
        },
      })
      ..ok('getAlbum.view', {
        'album': {
          'id': 'al1',
          'name': '叶惠美',
          'artist': '周杰伦',
          'song': [
            {'id': 's1', 'title': '晴天'},
          ],
        },
      })
      ..ok('getArtists.view')
      ..ok('getPlaylists.view')
      ..ok('getGenres.view')
      ..ok('getStarred2.view');

    await tester.pumpWidget(app(transport));
    await tester.pumpAndSettle();

    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('叶惠美'));
    await tester.pumpAndSettle();

    expect(find.text('晴天'), findsOneWidget, reason: '层级页经会话取到了曲目');
    expect(find.textContaining('会话未注入'), findsNothing);
    expect(find.text('登录状态异常，请重试'), findsNothing);

    // 收藏写在同一个作用域里：`starStoreProvider` 依赖会话，漏声明依赖同样会抛。
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pumpAndSettle();

    expect(transport.lastEndpoint, 'star.view');
    expect(transport.lastQuery['albumId'], 'al1');
  });
}

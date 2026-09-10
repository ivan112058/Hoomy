import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/main.dart';

void main() {
  setUp(() {
    // 每个用例从「本机无凭据」开始，避免用例间互相污染。
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('未登录时显示登录页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoomyApp()));
    await tester.pumpAndSettle();

    expect(find.text('连接 Navidrome'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('播放列表'), findsNothing);
  });

  testWidgets('已登录时进入主壳并显示五个 Tab', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'navidrome_credentials':
          '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 隔离网络：本用例只验证根路由与外壳结构，页面数据由各页自测覆盖。
          subsonicClientProvider.overrideWithValue(null),
        ],
        child: const HoomyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接 Navidrome'), findsNothing);
    for (final label in ['播放列表', '艺术家', '专辑', '歌曲', '更多']) {
      expect(find.text(label), findsOneWidget, reason: '缺少 Tab: $label');
    }
  });
}

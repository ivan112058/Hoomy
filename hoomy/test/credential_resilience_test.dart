import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/credentials/credential_store.dart';
import 'package:hoomy/data/http/http_transport.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';
import 'package:hoomy/main.dart';

import 'fake_transport.dart';

/// 票据 17：安全存储不可用时的降级路径。
///
/// 真机上无法制造 keystore 失败（目标电视上它其实工作正常），因此「失败」这一
/// 条件由替身注入。断言的是**对外行为**：失败时应用仍然可用 —— 不是插件内部
/// 调了哪些方法。
class _FailingSecureStorage extends FlutterSecureStorage {
  const _FailingSecureStorage();

  static final _error = PlatformException(
    code: 'Exception encountered',
    message: 'Failed to load generated key pair from keystore',
  );

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw _error;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw _error;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw _error;
}

/// 安全存储坏掉的本机环境。
CredentialStore failingStore() => CredentialStore(const _FailingSecureStorage());

Dio _transportWith(FakeTransport transport) => Dio()..httpClientAdapter = transport;

ProviderContainer _container(FakeTransport transport, {CredentialStore? store}) =>
    ProviderContainer(
      overrides: [
        httpTransportProvider.overrideWithValue(_transportWith(transport)),
        if (store != null) credentialStoreProvider.overrideWithValue(store),
      ],
    );

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CredentialStore', () {
    test('安全存储读失败时按「未登录」处理，不把异常抛给启动路径', () async {
      expect(await failingStore().read(), isNull);
    });

    test('安全存储写失败时抛出，由调用方决定怎么降级', () async {
      await expectLater(
        failingStore().write(
          const SubsonicCredentials(
            serverUrl: 'http://nas.local:4533',
            username: 'alice',
            password: 'hunter2',
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('安全存储正常时照旧读写（对照组）', () async {
      const credentials = SubsonicCredentials(
        serverUrl: 'http://nas.local:4533',
        username: 'alice',
        password: 'hunter2',
      );
      final store = CredentialStore();

      await store.write(credentials);

      expect((await store.read())?.username, 'alice');
    });
  });

  group('AuthController 登录失败', () {
    test('凭据校验失败时抛出，登录态保持「未登录」而不是错误态', () async {
      final container = _container(
        FakeTransport()..fail('ping.view', 40, 'Wrong username or password'),
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      await expectLater(
        container
            .read(authProvider.notifier)
            .login('nas.local:4533', 'alice', 'wrong'),
        throwsA(isA<SubsonicException>()),
      );

      expect(container.read(authProvider).hasError, isFalse);
      expect(container.read(authProvider).value, isNull);
    });

    test('凭据写入失败时仍完成登录，并标记「未持久化」', () async {
      final container = _container(
        FakeTransport()..ok('ping.view'),
        store: failingStore(),
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .login('nas.local:4533', 'alice', 'hunter2');

      expect(container.read(authProvider).value?.username, 'alice');
      expect(container.read(authProvider).hasError, isFalse);
      expect(container.read(authProvider.notifier).credentialsPersisted, isFalse);
    });

    test('凭据写入成功时标记「已持久化」', () async {
      final container = _container(FakeTransport()..ok('ping.view'));
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .login('nas.local:4533', 'alice', 'hunter2');

      expect(container.read(authProvider.notifier).credentialsPersisted, isTrue);
    });
  });

  group('登录页', () {
    testWidgets('密码错误时停在登录页并提示，而不是整页报错', (tester) async {
      final transport = FakeTransport()
        ..fail('ping.view', 40, 'Wrong username or password');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [httpTransportProvider.overrideWithValue(_transportWith(transport))],
          child: const HoomyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'nas.local:4533');
      await tester.enterText(fields.at(1), 'alice');
      await tester.enterText(fields.at(2), 'wrong');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('连接 Navidrome'), findsOneWidget, reason: '应仍停在登录页');
      expect(find.text('用户名或密码错误'), findsOneWidget);
      expect(find.textContaining('读取登录状态失败'), findsNothing);
    });

    testWidgets('凭据存不下来时仍然进应用，并明确告知下次要重登', (tester) async {
      final transport = FakeTransport()..ok('ping.view');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            httpTransportProvider.overrideWithValue(_transportWith(transport)),
            credentialStoreProvider.overrideWithValue(failingStore()),
            // 登录后的曲库取数与本用例无关，隔离掉网络。
            subsonicClientProvider.overrideWithValue(null),
          ],
          child: const HoomyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'nas.local:4533');
      await tester.enterText(fields.at(1), 'alice');
      await tester.enterText(fields.at(2), 'hunter2');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(find.text('播放列表'), findsOneWidget, reason: '登录应成功并进入应用');
      expect(
        find.text('凭据未能保存到本机，下次打开需要重新登录'),
        findsOneWidget,
        reason: '降级必须让用户知道，不能悄悄丢掉持久化',
      );
    });
  });
}

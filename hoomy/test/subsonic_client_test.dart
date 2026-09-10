import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/subsonic_client.dart';

import 'fake_transport.dart';

/// S1 接缝：认证参数、请求组装、信封解包、错误映射与媒体 URL。
/// 全部用固定响应验证，不回放真实网络。
void main() {
  group('认证参数与请求组装', () {
    test('每次请求重新生成 salt，且 t = md5(密码 + salt)', () async {
      final transport = FakeTransport()..ok('ping.view');
      final client = fakeClient(transport);

      await client.ping();
      final first = transport.lastQuery;
      await client.ping();
      final second = transport.lastQuery;

      expect(first['u'], 'alice');
      expect(first['v'], '1.16.1');
      expect(first['c'], 'hoomy');
      expect(first['f'], 'json');
      expect(first['s'], hasLength(12));
      expect(
        first['t'],
        md5.convert(utf8.encode('hunter2${first['s']}')).toString(),
      );

      // salt 每次请求重新生成，否则 md5(密码 + salt) 可被重放。
      expect(second['s'], isNot(first['s']));
      expect(
        second['t'],
        md5.convert(utf8.encode('hunter2${second['s']}')).toString(),
      );
    });

    test('请求打到 /rest/<endpoint>，并带上调用参数', () async {
      final transport = FakeTransport()..ok('search3.view');

      await fakeClient(transport).search3Songs(
        query: '周杰伦',
        songCount: 500,
        songOffset: 100,
      );

      expect(transport.lastRequest.method, 'GET');
      expect(transport.lastRequest.uri.path, '/rest/search3.view');
      expect(transport.lastQuery['query'], '周杰伦');
      expect(transport.lastQuery['songCount'], '500');
      expect(transport.lastQuery['songOffset'], '100');
    });

    test('客户端名可配置', () async {
      final transport = FakeTransport()..ok('ping.view');

      await fakeClient(transport, clientName: 'hoomy-tv').ping();

      expect(transport.lastQuery['c'], 'hoomy-tv');
    });
  });

  group('subsonic-response 信封解包', () {
    test('status=ok 时正常返回', () async {
      final transport = FakeTransport()..ok('ping.view');

      await fakeClient(transport).ping();

      expect(transport.requests, hasLength(1));
    });

    test('status=failed 时按 error.code 与 error.message 抛领域异常', () async {
      final transport = FakeTransport()
        ..fail('ping.view', 40, 'Wrong username or password');

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.code, 'code', 40)
              .having((e) => e.message, 'message', 'Wrong username or password')
              .having((e) => e.isAuthError, 'isAuthError', isTrue),
        ),
      );
    });

    test('error 节点缺失时不崩，退回兜底错误码与消息', () async {
      final transport = FakeTransport()
        ..ok('ping.view', {'status': 'failed'});

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.code, 'code', 0)
              .having((e) => e.message, 'message', '未知错误'),
        ),
      );
    });

    test('缺少 subsonic-response 节点时提示不是 Subsonic 格式', () async {
      final transport = FakeTransport()
        ..responder = (_) => jsonResponse({'hello': 'world'});

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.message, 'message', contains('Subsonic')),
        ),
      );
    });

    test('地址指向非 Subsonic 服务（HTML 200）时给可读提示而不是类型错误', () async {
      final transport = FakeTransport()
        ..responder = (_) =>
            textResponse('<html><body>router admin</body></html>');

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.message, 'message', contains('Subsonic')),
        ),
      );
    });

    test('空响应体提示服务器返回了空响应', () async {
      final transport = FakeTransport()
        ..responder = (_) => ResponseBody.fromString(
              '',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.message, 'message', '服务器返回了空响应'),
        ),
      );
    });
  });

  group('网络错误映射为可读中文提示', () {
    Future<SubsonicException> failureFrom(
      DioException Function(RequestOptions options) build,
    ) async {
      final transport = FakeTransport()..thrower = build;
      try {
        await fakeClient(transport).ping();
      } on SubsonicException catch (e) {
        return e;
      }
      fail('应当抛出 SubsonicException');
    }

    test('连接超时', () async {
      final e = await failureFrom(
        (o) => DioException.connectionTimeout(
          timeout: const Duration(seconds: 5),
          requestOptions: o,
        ),
      );
      expect(e.message, '连接服务器超时');
    });

    test('接收超时', () async {
      final e = await failureFrom(
        (o) => DioException.receiveTimeout(
          timeout: const Duration(seconds: 5),
          requestOptions: o,
        ),
      );
      expect(e.message, '连接服务器超时');
    });

    test('无法连接', () async {
      final e = await failureFrom(
        (o) => DioException.connectionError(
          requestOptions: o,
          reason: 'Connection refused',
        ),
      );
      expect(e.message, '无法连接到服务器，请检查地址与网络');
    });

    test('HTTP 404 提示地址指向的不是 Navidrome', () async {
      final transport = FakeTransport()
        ..responder = (_) => textResponse('not found', statusCode: 404);

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.message, 'message', contains('Navidrome')),
        ),
      );
    });

    test('HTTP 503 提示服务器暂时不可用', () async {
      final transport = FakeTransport()
        ..responder = (_) => textResponse('unavailable', statusCode: 503);

      await expectLater(
        fakeClient(transport).ping(),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.message, 'message', '服务器暂时不可用'),
        ),
      );
    });
  });

  group('媒体 URL', () {
    test('streamUri 请求原始流（format=raw）并带认证参数', () {
      final client = fakeClient(FakeTransport());

      final uri = client.streamUri('song-1');

      expect(uri.path, '/rest/stream.view');
      expect(uri.queryParameters['id'], 'song-1');
      expect(uri.queryParameters['format'], 'raw');
      expect(uri.queryParameters['u'], 'alice');
      expect(
        uri.queryParameters['t'],
        md5.convert(utf8.encode('hunter2${uri.queryParameters['s']}'))
            .toString(),
      );
    });

    test('coverArtUri 带 id 与可选 size，且两次调用的 salt 不同', () {
      final client = fakeClient(FakeTransport());

      final sized = client.coverArtUri('cover-1', size: 300);
      expect(sized.path, '/rest/getCoverArt.view');
      expect(sized.queryParameters['id'], 'cover-1');
      expect(sized.queryParameters['size'], '300');

      final plain = client.coverArtUri('cover-1');
      expect(plain.queryParameters.containsKey('size'), isFalse);
      expect(
        plain.queryParameters['s'],
        isNot(sized.queryParameters['s']),
      );
    });
  });
}

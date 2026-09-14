import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:hoomy/data/subsonic/subsonic_client.dart';

/// S1 接缝（HTTP 传输）的测试基座：把 Dio 的 adapter 换成固定响应，
/// 于是「认证参数 → 请求组装 → 信封解包 → 领域模型」整条链路都能在无网络下验证。

/// 固定测试凭据。
const testCredentials = SubsonicCredentials(
  serverUrl: 'http://nas.local:4533',
  username: 'alice',
  password: 'hunter2',
);

/// 假 HTTP 传输。默认按端点名返回注册好的 `subsonic-response` 信封。
class FakeTransport implements HttpClientAdapter {
  /// 收到的全部请求，按先后顺序。
  final List<RequestOptions> requests = [];

  final Map<String, Map<String, Object?>> _okEnvelopes = {};

  /// 需要非 200 或非 JSON 响应时使用；优先于已注册的端点。
  ResponseBody Function(RequestOptions options)? responder;

  /// 需要模拟网络层异常时使用；优先于 [responder]。
  DioException Function(RequestOptions options)? thrower;

  /// 非 null 时所有响应先等它完成：在测试里制造「请求在途」的窗口，
  /// 用于观察乐观更新与同目标互斥（票据 12）。
  Future<void>? gate;

  /// 注册一个 `status=ok` 的固定响应（[body] 是信封内容，无需写 status）。
  void ok(String endpoint, [Map<String, Object?> body = const {}]) {
    _okEnvelopes[endpoint] = {'status': 'ok', 'version': '1.16.1', ...body};
  }

  /// 注册一个 `status=failed` 的固定响应，模拟服务端返回的 Subsonic 错误。
  void fail(String endpoint, int code, String message) {
    _okEnvelopes[endpoint] = {
      'status': 'failed',
      'error': {'code': code, 'message': message},
    };
  }

  RequestOptions get lastRequest => requests.last;

  /// 最后一次请求的端点名，如 `ping.view`。
  String get lastEndpoint => lastRequest.uri.pathSegments.last;

  /// 最后一次请求的查询参数。
  Map<String, String> get lastQuery => lastRequest.uri.queryParameters;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    final gate = this.gate;
    if (gate != null) await gate;

    final thrown = thrower;
    if (thrown != null) throw thrown(options);
    final respond = responder;
    if (respond != null) return respond(options);

    final body = _okEnvelopes[options.uri.pathSegments.last];
    if (body == null) {
      throw StateError('FakeTransport 未注册端点：${options.uri.pathSegments.last}');
    }
    return jsonResponse({'subsonic-response': body});
  }

  @override
  void close({bool force = false}) {}
}

/// 构造一个 JSON 响应体。
ResponseBody jsonResponse(Object body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 构造纯文本响应体（如 HTML 错误页）。
ResponseBody textResponse(String body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
      },
    );

/// 用假传输构造客户端，测试过程不会发起真实网络请求。
SubsonicClient fakeClient(
  FakeTransport transport, {
  SubsonicCredentials credentials = testCredentials,
  String clientName = 'hoomy',
}) {
  final dio = Dio();
  dio.httpClientAdapter = transport;
  return SubsonicClient(
    credentials: credentials,
    dio: dio,
    clientName: clientName,
  );
}

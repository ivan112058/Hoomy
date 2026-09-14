import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用**唯一**的 HTTP 传输（ADR-0015 决策 5）。
///
/// 登录校验、协议客户端、封面下载都从这里取传输，于是超时、重试、TLS 这类
/// 传输策略只写一遍；测试也只需替换这一处，就能同时驱动登录、曲库与封面三条链路。
///
/// 生产在 `main()` 里构造并 override —— 封面缓存要在 `runApp` 之前就拿到它。
/// 测试 override 成装了假 adapter 的 `Dio`。
final httpTransportProvider = Provider<Dio>((ref) => createHttpTransport());

/// 生产传输的唯一构造点。别在别处再写 `Dio()`。
Dio createHttpTransport() => Dio();

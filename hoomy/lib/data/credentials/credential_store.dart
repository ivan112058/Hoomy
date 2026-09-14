import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../subsonic/subsonic_client.dart';

/// 凭据的安全存储。MVP 只保存一组（单服务器单用户）。
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'navidrome_credentials';

  final FlutterSecureStorage _storage;

  /// 读不到凭据就按「未登录」处理 —— 安全存储坏掉（keystore 异常、条目损坏）
  /// 只该让用户重新登录一次，**绝不能让启动路径抛异常**：根路由会把
  /// 未捕获的读失败渲染成整页错误，应用因此没有出路（ADR-0014）。
  Future<SubsonicCredentials?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (error) {
      debugPrint('[credentials] 读取安全存储失败，按未登录处理: $error');
      return null;
    }
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubsonicCredentials(
        serverUrl: map['serverUrl'] as String,
        username: map['username'] as String,
        password: map['password'] as String,
      );
    } catch (error) {
      debugPrint('[credentials] 本机凭据不可解析，按未登录处理: $error');
      return null;
    }
  }

  Future<void> write(SubsonicCredentials credentials) =>
      _storage.write(key: _key, value: jsonEncode(_toJson(credentials)));

  Future<void> clear() => _storage.delete(key: _key);

  Map<String, dynamic> _toJson(SubsonicCredentials credentials) => {
        'serverUrl': credentials.serverUrl,
        'username': credentials.username,
        'password': credentials.password,
      };
}

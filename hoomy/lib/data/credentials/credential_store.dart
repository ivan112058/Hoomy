import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../subsonic/subsonic_client.dart';

/// 凭据的安全存储。MVP 只保存一组（单服务器单用户）。
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'navidrome_credentials';

  final FlutterSecureStorage _storage;

  Future<SubsonicCredentials?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubsonicCredentials(
        serverUrl: map['serverUrl'] as String,
        username: map['username'] as String,
        password: map['password'] as String,
      );
    } on FormatException {
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

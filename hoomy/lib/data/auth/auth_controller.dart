import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../credentials/credential_store.dart';
import '../http/http_transport.dart';
import '../subsonic/subsonic_client.dart';

/// 全局登录态：null 表示未登录（显示登录页）。
class AuthController extends AsyncNotifier<SubsonicCredentials?> {
  bool _credentialsPersisted = true;

  /// 最近一次登录有没有把凭据落盘。false 表示本次会话可用、重启后要重登。
  bool get credentialsPersisted => _credentialsPersisted;

  @override
  Future<SubsonicCredentials?> build() async {
    final store = ref.read(credentialStoreProvider);
    return store.read();
  }

  /// 校验并登录；成功后持久化凭据。失败抛 [SubsonicException] 或 [FormatException]。
  ///
  /// 这里**只在成功时改全局状态**：一次登录尝试失败（密码错、连不上、安全存储
  /// 坏）是登录页要呈现的错误，不该把整个应用推进错误态。
  Future<void> login(String serverUrl, String username, String password) async {
    final credentials = SubsonicCredentials.fromInput(
        serverUrl: serverUrl, username: username, password: password);
    final client = SubsonicClient(
      credentials: credentials,
      dio: ref.read(httpTransportProvider),
    );
    await client.ping();
    _credentialsPersisted = await _persist(credentials);
    state = AsyncData(credentials);
  }

  /// 落盘失败不算登录失败：这次仍然能听歌，只是下次打开要重新登录。
  Future<bool> _persist(SubsonicCredentials credentials) async {
    try {
      await ref.read(credentialStoreProvider).write(credentials);
      return true;
    } catch (error) {
      debugPrint('[auth] 凭据未能落盘，本次会话仍可用: $error');
      return false;
    }
  }

  /// 退出登录并清除本地凭据（不影响服务端数据）。
  Future<void> logout() async {
    await ref.read(credentialStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final authProvider =
    AsyncNotifierProvider<AuthController, SubsonicCredentials?>(AuthController.new);

final credentialStoreProvider = Provider<CredentialStore>((ref) => CredentialStore());

/// 当前登录用户的 API 客户端；未登录时为 null。
///
/// 用应用唯一的 HTTP 传输（ADR-0015 决策 5）。
final subsonicClientProvider = Provider<SubsonicClient?>((ref) {
  final credentials = ref.watch(authProvider).value;
  if (credentials == null) return null;
  return SubsonicClient(
    credentials: credentials,
    dio: ref.watch(httpTransportProvider),
  );
});

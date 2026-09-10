import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../credentials/credential_store.dart';
import '../subsonic/subsonic_client.dart';

/// 全局登录态：null 表示未登录（显示登录页）。
class AuthController extends AsyncNotifier<SubsonicCredentials?> {
  @override
  Future<SubsonicCredentials?> build() async {
    final store = ref.read(credentialStoreProvider);
    return store.read();
  }

  /// 校验并登录；成功后持久化凭据。失败抛 [SubsonicException] 或 [FormatException]。
  Future<void> login(String serverUrl, String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credentials =
          SubsonicCredentials.fromInput(
              serverUrl: serverUrl, username: username, password: password);
      final client = SubsonicClient(credentials: credentials);
      await client.ping();
      await ref.read(credentialStoreProvider).write(credentials);
      return credentials;
    });
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
final subsonicClientProvider = Provider<SubsonicClient?>((ref) {
  final credentials = ref.watch(authProvider).value;
  if (credentials == null) return null;
  return SubsonicClient(credentials: credentials);
});

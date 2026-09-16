import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/form_factor.dart';
import '../../data/auth/auth_controller.dart';
import '../../data/http/http_transport.dart';
import '../../data/session/session.dart';
import '../../data/session/session_providers.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../shell/home_shell.dart';
import '../shell/tv_home_shell.dart';
import 'login_page.dart';

/// 登录闸口：决定「当前有没有会话」的唯一位置（ADR-0015 决策 2）。
///
/// 有会话就进主界面，没有就是登录页 —— 主界面之内不再有第二种形态。会话在这里
/// 以**嵌套作用域**注入（[sessionProvider]），所以主界面之内它在类型上不可能为空，
/// 页面不必再写「没有数据源就画空白」。
class LoginGate extends ConsumerStatefulWidget {
  const LoginGate({super.key});

  @override
  ConsumerState<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends ConsumerState<LoginGate> {
  SubsonicCredentials? _credentials;
  Session? _session;

  /// 同一份凭据下复用同一个会话实例。
  ///
  /// 外壳因主题、窗口尺寸之类无关原因重建时，会话不重算，页面也就不会重取数
  /// （票据 02 的验收项）。凭据按值比较（[SubsonicCredentials] 有值相等）：
  /// 重新读一次安全存储得到的仍是同一份凭据，不该因此换会话。
  Session _sessionFor(SubsonicCredentials credentials) {
    final current = _session;
    if (current != null && _credentials == credentials) return current;
    _credentials = credentials;
    return _session = Session(
      credentials: credentials,
      transport: ref.read(httpTransportProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return switch (auth) {
      AsyncLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AsyncError(:final error) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('读取登录状态失败：$error', textAlign: TextAlign.center),
          ),
        ),
      ),
      _ => auth.value == null
          ? const LoginPage()
          : _SessionScope(
              session: _sessionFor(auth.value!),
              child: HoomyFormFactorScope.isTv(context)
                  ? const TvHomeShell()
                  : const HomeShell(),
            ),
    };
  }
}

/// 会话的注入点：用嵌套作用域把非空会话交给主界面。
///
/// 测试也在这里注入「真会话 + 假传输」（ADR-0015 测试决策）。
class _SessionScope extends StatelessWidget {
  const _SessionScope({required this.session, required this.child});

  final Session session;
  final Widget child;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [sessionProvider.overrideWithValue(session)],
    child: child,
  );
}

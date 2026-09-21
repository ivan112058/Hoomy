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

/// 会话的作用域：把**非空**会话交给主界面（ADR-0015 决策 2 的注入点）。
///
/// 它必须挂在 `MaterialApp` 的 `builder` 上（Navigator **之上**），不能只包住
/// `home` 路由：闸口 push 出去的详情页、播放页在 Overlay 上是 home 路由的**兄弟**，
/// 作用域只包 home 时它们读不到会话（票据 03 修正的缺陷）。
///
/// 注入的是可空的 [sessionOrNullProvider]（[sessionProvider] 由它派生出非空
/// 形态），播放层因此能如实看到「没有会话」并让控制器为空（票据 04）。
///
/// 没有凭据时不注入：登录页与「读取登录状态失败」都不需要会话。
class SessionScope extends ConsumerStatefulWidget {
  const SessionScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends ConsumerState<SessionScope> {
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
    final credentials = ref.watch(authProvider).value;
    if (credentials == null) return widget.child;
    return ProviderScope(
      overrides: [
        sessionOrNullProvider.overrideWithValue(_sessionFor(credentials)),
      ],
      child: widget.child,
    );
  }
}

/// 登录闸口：决定「当前有没有会话」的唯一位置（ADR-0015 决策 2）。
///
/// 有会话就进主界面，没有就是登录页 —— 主界面之内不再有第二种形态。会话由
/// [SessionScope] 在 Navigator 之上注入，所以主界面之内（含 push 出来的层级页）
/// 它在类型上不可能为空，页面不必再写「没有数据源就画空白」。
class LoginGate extends ConsumerStatefulWidget {
  const LoginGate({super.key});

  @override
  ConsumerState<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends ConsumerState<LoginGate> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    // 会话消失是**路由事件**（ADR-0015 决策 3）：路由在这里订阅会话状态，一旦从
    // 「有会话」变成「没有会话」（登出或凭据失效），就重置导航栈回登录页 ——
    // 压在主界面之上的层级路由（例如设置页）一并清掉，不再依赖调用点记得弹栈。
    ref.listen(authProvider, (previous, next) {
      final hadSession = previous?.value != null;
      final hasSession = next.value != null;
      if (hadSession && !hasSession) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
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
          : HoomyFormFactorScope.isTv(context)
          ? const TvHomeShell()
          : const HomeShell(),
    };
  }
}

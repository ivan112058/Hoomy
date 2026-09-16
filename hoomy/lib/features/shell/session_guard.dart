import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../../data/auth/auth_controller.dart';
import '../../data/session/session_providers.dart';
import '../shared/error_retry_view.dart';

/// 外壳的统一兜底：主界面之内「会话必不为空」这条不变量被破坏时，给出可读原因
/// 与重试入口，而不是一片空白或一次崩溃。
///
/// 正常路径上这是死代码 —— 登录闸口挂主界面时已经注入会话（[sessionProvider]），
/// 页面直接取用。它存在只为让不变量被破坏时的表现可控，且有测试证明它**只在**
/// 那种情况下才会出现（票据 02 的验收项）。
class SessionGuard extends ConsumerWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      ref.watch(sessionProvider);
    } on ProviderException {
      // 会话不在，页面连「我要什么数据」都无从谈起：这里只留一个重试入口，
      // 重读登录态 —— 凭据还在就重新注入会话，不在了就回登录页。
      return ErrorRetryView(
        message: '登录状态异常，请重试',
        onRetry: () => ref.invalidate(authProvider),
      );
    }
    return child;
  }
}

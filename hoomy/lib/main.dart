import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/hoomy_theme.dart';
import 'data/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/shell/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: HoomyApp()));
}

/// Hoomy：局域网 NAS 音乐播放器（Navidrome 客户端）。
class HoomyApp extends StatelessWidget {
  const HoomyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hoomy',
      debugShowCheckedModeBanner: false,
      theme: hoomyLightTheme(),
      darkTheme: hoomyDarkTheme(),
      // 主题策略：浅色优先，深色跟随系统。
      themeMode: ThemeMode.system,
      home: const _RootRouter(),
    );
  }
}

/// 根路由：按登录态决定显示登录页还是主壳。
class _RootRouter extends ConsumerWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      _ => auth.value == null ? const LoginPage() : const HomeShell(),
    };
  }
}

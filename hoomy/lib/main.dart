import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/form_factor.dart';
import 'core/theme/hoomy_theme.dart';
import 'data/auth/auth_controller.dart';
import 'data/cover/cover_cache_provider.dart';
import 'data/settings/theme_mode_controller.dart';
import 'features/auth/login_page.dart';
import 'features/shell/home_shell.dart';
import 'features/shell/tv_home_shell.dart';
import 'player/hoomy_audio_handler.dart';
import 'player/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 封面磁盘缓存（票据 07）：启动时把目录与下载器准备好。拿不到目录就没有
  // 磁盘缓存，界面直连服务端，不影响使用。
  final coverCache = await openCoverCache();

  // 系统媒体会话（票据 07）：Android 的媒体通知／TV 遥控器媒体键依赖它。
  // 启动失败只是失去系统集成，不能拦下 App。
  final audioHandler = await _startAudioService();

  runApp(
    ProviderScope(
      overrides: [
        if (coverCache != null)
          coverCacheProvider.overrideWithValue(coverCache),
        if (audioHandler != null)
          audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const HoomyApp(),
    ),
  );
}

Future<HoomyAudioHandler?> _startAudioService() async {
  try {
    return await HoomyAudioHandler.init();
  } catch (_) {
    return null;
  }
}

/// Hoomy：局域网 NAS 音乐播放器（Navidrome 客户端）。
class HoomyApp extends ConsumerWidget {
  const HoomyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题模式存在本机（票据 15）；读取期间按「跟随系统」显示，不阻塞首帧。
    final themeMode = ref.watch(currentThemeModeProvider);
    // 平台即形态：Android 只做 TV（ADR-0013），不做机型探测。
    final formFactor = platformFormFactor;
    return MaterialApp(
      title: 'Hoomy',
      debugShowCheckedModeBanner: false,
      theme: hoomyLightTheme(),
      darkTheme: hoomyDarkTheme(),
      // 主题策略：浅色优先，深色跟随系统；设置页可改为手动浅色／深色。
      themeMode: themeMode,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        return HoomyFormFactorScope(
          formFactor: formFactor,
          // TV 上方向键**只**用于移动焦点：滑块等部件不能再把左右键当作
          // 「微调数值」（这是 Flutter 给电视界面的导航模式）。不设这一项时
          // 方向键是「传统」语义，文本输入框还会把上下键吞掉、焦点出不去。
          child: formFactor == HoomyFormFactor.tv
              ? MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    navigationMode: NavigationMode.directional,
                  ),
                  child: content,
                )
              : content,
        );
      },
      home: const _RootRouter(),
    );
  }
}

/// 根路由：按登录态与平台形态决定显示登录页、手机外壳还是 TV 外壳。
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
      _ => auth.value == null
          ? const LoginPage()
          : HoomyFormFactorScope.isTv(context)
          ? const TvHomeShell()
          : const HomeShell(),
    };
  }
}

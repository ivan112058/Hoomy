import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_store.dart';

/// 本机设置存储。
final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

/// 主题模式（票据 15）：跟随系统／浅色／深色，选择持久化在本机。
///
/// 启动时从 [SettingsStore] 读回；读不到（首次启动、存储不可用、值损坏）按
/// 「跟随系统」处理。切换时**先改状态再落盘**：界面立刻生效，落盘失败只影响
/// 下次启动的取值（与收藏的乐观更新同口径）。
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final store = ref.read(settingsStoreProvider);
    return await store.readThemeMode() ?? ThemeMode.system;
  }

  /// 切换主题模式；立刻生效，随后尽力落盘。
  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(settingsStoreProvider).writeThemeMode(mode);
  }
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
    );

/// 界面消费的主题模式：本机偏好还没读回来时按「跟随系统」显示。
///
/// 兜底规则只写在这一处，消费方（外壳、设置页）各自 `?? ThemeMode.system`
/// 会把它复制多份，改默认值时容易漏。
final currentThemeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeModeProvider).value ?? ThemeMode.system,
);

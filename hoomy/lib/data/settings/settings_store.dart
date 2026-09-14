import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机设置的落盘读写（票据 15）。
///
/// 只放**与本机有关、不涉及凭据**的偏好（目前只有主题模式）：凭据走
/// `CredentialStore` 的安全存储，两者不混用。
///
/// 与队列持久化同口径，读写是**尽力而为**：存储不可用或数据损坏时退回
/// 「没设置过」，绝不把异常抛给启动或界面。
class SettingsStore {
  /// 可选注入 [SharedPreferences]（测试用）；缺省时首次读写时惰性获取。
  SettingsStore([this._preferences]);

  /// 主题模式键；存 [ThemeMode] 的枚举名。
  static const themeModeKey = 'theme_mode';

  SharedPreferences? _preferences;

  /// 惰性取存储；平台不支持或插件缺失时返回 null，由各方法降级为无操作。
  Future<SharedPreferences?> get _prefs async {
    final cached = _preferences;
    if (cached != null) return cached;
    try {
      return _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// 读取主题模式；没设置过、值不可识别或存储不可用时为 null
  /// （调用方按「跟随系统」处理）。
  Future<ThemeMode?> readThemeMode() async {
    try {
      final raw = (await _prefs)?.getString(themeModeKey);
      if (raw == null) return null;
      for (final mode in ThemeMode.values) {
        if (mode.name == raw) return mode;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 写入主题模式。写不进去只影响下次启动的默认值，本次切换照常生效。
  Future<void> writeThemeMode(ThemeMode mode) async {
    try {
      await (await _prefs)?.setString(themeModeKey, mode.name);
    } catch (_) {
      // 与读路径同口径：设置存不下不是致命错误。
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/auth/auth_controller.dart';
import '../../data/cover/cover_cache_provider.dart';
import '../../data/settings/theme_mode_controller.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_button.dart';
import '../shared/hoomy_list_row.dart';

/// 设置页：主题切换、封面缓存占用与清除、退出登录。
///
/// 三项都只影响本机：主题存本机偏好，缓存是磁盘上的封面文件，退出登录清的是
/// 本机凭据 —— 唯一的服务端交互是播放/浏览本身，设置页不发任何写请求。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(currentThemeModeProvider);
    return PageScaffold(
      title: '设置',
      body: ListView(
        children: [
          const SectionHeader(title: '主题'),
          for (final mode in ThemeMode.values)
            _ThemeModeRow(mode: mode, selected: mode == themeMode),
          const SectionHeader(title: '存储'),
          const _CoverCacheRow(),
          const SectionHeader(title: '账号'),
          const _LogoutRow(),
        ],
      ),
    );
  }
}

/// 主题模式选项：选中项行尾打勾。
class _ThemeModeRow extends ConsumerWidget {
  const _ThemeModeRow({required this.mode, required this.selected});

  final ThemeMode mode;
  final bool selected;

  static const _labels = {
    ThemeMode.system: '跟随系统',
    ThemeMode.light: '浅色',
    ThemeMode.dark: '深色',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HoomyListRow(
      title: _labels[mode]!,
      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(mode),
      trailing: selected
          ? (state) => Icon(
              Icons.check,
              // 高亮（按下 / 聚焦）时随整行变白，常态用播放红标出当前选择。
              color: state.active
                  ? state.foreground
                  : HoomyPalette.of(context).playing,
            )
          : null,
    );
  }
}

/// 封面缓存行：显示占用并提供清除。
class _CoverCacheRow extends ConsumerStatefulWidget {
  const _CoverCacheRow();

  @override
  ConsumerState<_CoverCacheRow> createState() => _CoverCacheRowState();
}

class _CoverCacheRowState extends ConsumerState<_CoverCacheRow> {
  bool _clearing = false;

  Future<void> _clear() async {
    final cache = ref.read(coverCacheProvider);
    if (cache == null || _clearing) return;
    // 先取好 messenger：await 之后 context 可能已经失效。
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _clearing = true);
    try {
      await cache.clear();
      // `CoverCache.clear()` 是尽力而为的（单个文件删不掉不算失败），因此
      // 回头查一次真实占用再决定提示语，不无条件宣布「已清除」。
      final remaining = await cache.totalBytes();
      // 重新查询占用：清除后应显示 0，而不是清除前的旧值。
      ref.invalidate(coverCacheBytesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(remaining == 0 ? '已清除封面缓存' : '部分封面缓存未能清除'),
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCache = ref.watch(coverCacheProvider) != null;
    final bytes = ref.watch(coverCacheBytesProvider);

    return HoomyListRow(
      title: '封面缓存',
      subtitle: _subtitle(bytes, hasCache: hasCache),
      trailing: (state) => HoomyButton(
        onPressed: (!hasCache || _clearing) ? null : _clear,
        // 高亮（按下 / 聚焦）时随整行变白（`CONTEXT.md`「按压反馈」）；
        // 未高亮沿用按钮自己的常态色（播放红），禁用态保留默认的灰。
        child: Text(
          _clearing ? '清除中…' : '清除',
          style: state.active ? TextStyle(color: state.foreground) : null,
        ),
      ),
    );
  }

  /// 占用文案。没有缓存能力与占用为 0 分开说，避免让人以为「有 0 字节可清」。
  String _subtitle(AsyncValue<int?> bytes, {required bool hasCache}) {
    if (!hasCache) return '无磁盘缓存，封面直接请求服务端';
    return bytes.when(
      data: (value) => '当前占用 ${_formatCacheSize(value ?? 0)}',
      error: (_, _) => '无法读取缓存占用',
      loading: () => '正在计算…',
    );
  }
}

/// 退出登录行：确认后清本机凭据，根路由随之切回登录页。
class _LogoutRow extends ConsumerWidget {
  const _LogoutRow();

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本机保存的服务器地址、用户名与密码，需要重新登录。'
            '服务端上的歌单、收藏等数据不受影响。'),
        actions: [
          HoomyButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          HoomyButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    // 根路由已切到登录页，但设置页是压在它上面的 push 路由，要一并弹掉，
    // 否则用户会停留在设置页看不到登录页。
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HoomyListRow(
      title: '退出登录',
      onTap: () => _confirm(context, ref),
    );
  }
}

/// 缓存占用的人类可读文案：1024 进制，保留一位小数。
String _formatCacheSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

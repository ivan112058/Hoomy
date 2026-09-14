import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../player/playback_controller.dart';
import '../shared/hoomy_icon_button.dart';
import '../shared/hoomy_list_row.dart';
import 'playback_listenable.dart';

/// 播放失败提示条：显示引擎翻译好的可读文案，可手动关闭。
///
/// 播放失败不静默：错误经 [PlayerEngine.errorStream] → 状态机 → 控制器一路
/// 转发到这里，文案面向用户，原始描述只在开发期可读（`PlayerEngineError`）。
/// 换歌会清掉上一首的错误（控制器在队列变化时清空），不必手动关。
///
/// 挂在主壳底部、播放条之上，所以在哪个 Tab 都看得到。
class PlaybackErrorBanner extends StatelessWidget {
  const PlaybackErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaybackListenable(
      // 错误只在出现/清除时变，不必跟着进度每 ~200ms 重建。
      select: (controller) => controller.lastError,
      builder: (context, controller) =>
          _PlaybackErrorBannerBody(controller: controller),
    );
  }
}

class _PlaybackErrorBannerBody extends StatelessWidget {
  const _PlaybackErrorBannerBody({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.lastError;
    if (error == null) return const SizedBox.shrink();
    final palette = HoomyPalette.of(context);

    return Material(
      color: palette.surfaceRaised,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HoomyRowDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: palette.playing, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '播放失败：${error.message}',
                    style: TextStyle(
                      fontSize: HoomyDimens.listSubtitleFontSize,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                HoomyIconButton(
                  icon: Icons.close,
                  tooltip: '关闭',
                  color: palette.textSecondary,
                  iconSize: 20,
                  onPressed: controller.clearError,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

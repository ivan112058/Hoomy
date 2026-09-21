// Material 里也有一个同名的 RepeatMode（repeating_animation_builder），
// 这里只取本项目的播放循环模式。
import 'package:flutter/material.dart' hide RepeatMode;

import '../../player/playback_controller.dart';
import '../../player/playback_state_machine.dart';
import '../shared/hoomy_icon_button.dart';
import 'playback_listenable.dart';

/// 播放页的**五键中控**：循环、上一首、播放／暂停、下一首、随机。
///
/// 循环与随机只改状态机里的模式（票据 05），按钮图标由当前模式决定：
/// 循环在「关 → 全部 → 单曲」之间轮转，随机是开关。上一首／下一首／
/// 播放暂停与迷你播放条共用控制器上的同一组方法，行为一致。
///
/// 只订阅循环、随机与播放状态：进度每 ~200ms 推一次，不该带着按钮重绘
/// （进度条由播放页里单独的边界承接）。
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return PlaybackListenable(
      select: (controller) => (
        controller.snapshot.queue.repeatMode,
        controller.snapshot.queue.shuffle,
        controller.snapshot.playing,
      ),
      builder: (context, controller) {
        final queue = controller.snapshot.queue;
        final playing = controller.snapshot.playing;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlIcon(
              icon: repeatIcon(queue.repeatMode),
              tooltip: repeatTooltip(queue.repeatMode),
              // 循环不是开关而是三态轮转：关 → 全部 → 单曲 → 关。
              onPressed: () =>
                  controller.setRepeatMode(nextRepeatMode(queue.repeatMode)),
              active: queue.repeatMode != RepeatMode.off,
            ),
            _ControlIcon(
              icon: Icons.skip_previous,
              tooltip: '上一首',
              onPressed: controller.previous,
            ),
            _ControlIcon(
              icon: playing ? Icons.pause : Icons.play_arrow,
              tooltip: playing ? '暂停' : '播放',
              onPressed: controller.togglePlayPause,
              iconSize: 44,
            ),
            _ControlIcon(
              icon: Icons.skip_next,
              tooltip: '下一首',
              onPressed: controller.next,
            ),
            _ControlIcon(
              icon: Icons.shuffle,
              tooltip: queue.shuffle ? '关闭随机' : '随机播放',
              onPressed: () => controller.setShuffle(!queue.shuffle),
              active: queue.shuffle,
            ),
          ],
        );
      },
    );
  }
}

/// 循环三态的图标：关与全部用同一个循环图标（靠颜色区分开关），单曲加个 1。
IconData repeatIcon(RepeatMode mode) =>
    mode == RepeatMode.one ? Icons.repeat_one : Icons.repeat;

/// 循环按钮的提示文案，同时是当前模式的可见名称。
String repeatTooltip(RepeatMode mode) => switch (mode) {
  RepeatMode.off => '循环关闭',
  RepeatMode.all => '列表循环',
  RepeatMode.one => '单曲循环',
};

/// 循环模式的下一档：关 → 全部 → 单曲 → 关。
RepeatMode nextRepeatMode(RepeatMode mode) => switch (mode) {
  RepeatMode.off => RepeatMode.all,
  RepeatMode.all => RepeatMode.one,
  RepeatMode.one => RepeatMode.off,
};

/// 中控上的一个图标按钮：直角、56dp 点击区，激活态用播放红，聚焦时统一变白
/// 铺交互蓝（ADR-0013 决策 2）。
///
/// 留作一处命名与几何常量：五个键共用同一份尺寸，散在调用处会各自漂移。
class _ControlIcon extends StatelessWidget {
  const _ControlIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.iconSize = 28,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// 是否处于激活态（循环非关、随机打开）：图标转播放红。
  final bool active;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return HoomyIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      active: active,
      iconSize: iconSize,
      size: 56,
    );
  }
}

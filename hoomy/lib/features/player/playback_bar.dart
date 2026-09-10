import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../player/playback_controller.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_secondary_text.dart';
import 'playback_listenable.dart';

/// 底部播放条：当前曲目 + 播放/暂停 + 上一首/下一首 + 进度条。
///
/// 这是票据 06 用来让**播放可见、可控**的临时形态：点歌之后能立刻看到正在
/// 播什么、能暂停、能拖进度、能切歌。完整的迷你播放条（含封面、
/// `CONTEXT.md` 规定它**不显示进度**）属票据 08，本组件届时被它替换。
///
/// 没有播放会话时不占位（返回空盒子）。
class PlaybackBar extends StatelessWidget {
  const PlaybackBar({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaybackListenable(
      builder: (context, controller) =>
          _PlaybackBarBody(controller: controller),
    );
  }
}

class _PlaybackBarBody extends StatelessWidget {
  const _PlaybackBarBody({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    if (!session.hasSession) return const SizedBox.shrink();
    final song = session.currentSong;
    final palette = HoomyPalette.of(context);
    final subtitle = songSecondaryText(song);

    return Material(
      color: palette.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HoomyRowDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                _ControlButton(
                  icon: Icons.skip_previous,
                  tooltip: '上一首',
                  onPressed: controller.previous,
                ),
                _ControlButton(
                  icon: session.playing ? Icons.pause : Icons.play_arrow,
                  tooltip: session.playing ? '暂停' : '播放',
                  onPressed: controller.togglePlayPause,
                ),
                _ControlButton(
                  icon: Icons.skip_next,
                  tooltip: '下一首',
                  onPressed: controller.next,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: HoomyDimens.listTitleFontSize,
                          color: palette.playing,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: HoomyDimens.listSubtitleFontSize,
                            color: palette.textSecondary,
                          ),
                        ),
                      _SeekBar(
                        position: session.position,
                        duration: session.duration,
                        onSeek: controller.seek,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放控制按钮：直角、无内边距涟漪之外的装饰。
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: palette.textPrimary,
      icon: Icon(icon),
    );
  }
}

/// 可拖动进度条 + 左右时间。
///
/// 拖动过程中显示手指落点，松手才真正 seek —— 否则播放位置每 200ms 的更新
/// 会把滑块拽回去，拖不动。
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// 拖动中的落点；非 null 时忽略外部位置更新。
  double? _dragSeconds;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final total = widget.duration?.inMilliseconds.toDouble() ?? 0;
    final positionMs = widget.position.inMilliseconds.toDouble();
    final seekable = total > 0;
    final value = _dragSeconds ?? (seekable ? positionMs.clamp(0, total) : 0);
    final shown = Duration(milliseconds: value.round());

    return Row(
      children: [
        Text(_format(shown), style: _timeStyle(palette)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: palette.playing,
              thumbColor: palette.playing,
              inactiveTrackColor: palette.divider,
            ),
            child: Slider(
              // 拖动中禁用外部更新：value 由 _dragSeconds 决定。
              value: value,
              max: seekable ? total : 1,
              onChanged: seekable
                  ? (v) => setState(() => _dragSeconds = v)
                  : null,
              onChangeEnd: (v) {
                setState(() => _dragSeconds = null);
                widget.onSeek(Duration(milliseconds: v.round()));
              },
            ),
          ),
        ),
        Text(
          _format(widget.duration ?? Duration.zero),
          style: _timeStyle(palette),
        ),
      ],
    );
  }

  TextStyle _timeStyle(HoomyPalette palette) => TextStyle(
    fontSize: HoomyDimens.listSubtitleFontSize,
    color: palette.textSecondary,
  );

  /// `m:ss`；超过一小时显示 `h:mm:ss`（长 flac 常见）。
  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

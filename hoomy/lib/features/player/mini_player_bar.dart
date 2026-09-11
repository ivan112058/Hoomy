import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/subsonic/models.dart';
import '../../player/playback_controller.dart';
import '../shared/cover_art.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_secondary_text.dart';
import 'playback_listenable.dart';

/// 迷你播放条：底部 Tab 之上常驻的一条当前曲目控制条。
///
/// 显示当前曲目的封面、歌名、歌手，以及收藏、上一首、播放／暂停、下一首。
/// **不显示进度**——这是 `CONTEXT.md`「迷你播放条」的刻意克制，不要加进度线；
/// 需要进度与跳转的完整播放页属票据 09。
///
/// 点条身展开完整播放页：本组件把展开交给 [onTap]，由主壳接线（票据 09 落地）。
///
/// 没有当前曲目时**不占位**（返回空盒子），因此未播放时底部只剩 Tab。
///
/// 曲目变化与播放状态变化都经 [PlaybackListenable] 订阅控制器，
/// 与当前播放状态一致地即时更新。
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key, this.onTap});

  /// 点条身的回调；为 null 时条身不可点。
  final VoidCallback? onTap;

  /// 迷你播放条的**最小**高度（封面 40dp + 上下各 8dp）。
  ///
  /// 实际高度跟着内容走：系统字号放大时文字要高过 40dp，此时条随内容长高，
  /// 而不是把文字挤出边界（票据 06 记录的 TV 底部溢出就是这种挤法）。
  static const double height = 56.0;

  /// 封面边长。
  static const double coverSize = 40.0;

  @override
  Widget build(BuildContext context) {
    return PlaybackListenable(
      // 迷你条只显示「哪首、在不在播」，不显示进度，所以不被每 ~200ms 的
      // 进度通知拖着重绘。
      select: (controller) => controller.session.identity,
      builder: (context, controller) =>
          _MiniPlayerBarBody(controller: controller, onTap: onTap),
    );
  }
}

class _MiniPlayerBarBody extends StatelessWidget {
  const _MiniPlayerBarBody({required this.controller, this.onTap});

  final PlaybackController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final song = session.currentSong;
    // 没有当前曲目就不占位：底部 Tab 之上不留空白。
    if (song == null) return const SizedBox.shrink();
    final palette = HoomyPalette.of(context);

    return Material(
      color: palette.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HoomyRowDivider(),
          // 高度取「至少 56dp」而不是写死：字号放大时条跟着内容长高，
          // 不把歌名/歌手挤出边界。也刻意不写死内容高度 —— 约束死了就会
          // 像票据 06 的临时播放条那样在 TV 上溢出。
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MiniPlayerBar.height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onTap,
                      hoverColor: palette.surfaceRaised,
                      child: Row(
                        children: [
                          SizedBox(
                            width: MiniPlayerBar.coverSize,
                            height: MiniPlayerBar.coverSize,
                            child: CoverArt(
                              coverArtId: song.coverArtId,
                              size: MiniPlayerBar.coverSize.round(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _TrackText(song: song)),
                        ],
                      ),
                    ),
                  ),
                  // 收藏按钮在票据 12 之前先呈现为不可用：收藏是那票据的事，
                  // 不为了一个按钮把写路径（乐观更新与回滚）提前。
                  const _BarIcon(
                    icon: Icons.star_border,
                    tooltip: '收藏（票据 12 提供）',
                    onPressed: null,
                  ),
                  _BarIcon(
                    icon: Icons.skip_previous,
                    tooltip: '上一首',
                    onPressed: controller.previous,
                  ),
                  _BarIcon(
                    icon: session.playing ? Icons.pause : Icons.play_arrow,
                    tooltip: session.playing ? '暂停' : '播放',
                    onPressed: controller.togglePlayPause,
                  ),
                  _BarIcon(
                    icon: Icons.skip_next,
                    tooltip: '下一首',
                    onPressed: controller.next,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌名 + 歌手：歌名一行，歌手一行，都按可用宽度截断。
class _TrackText extends StatelessWidget {
  const _TrackText({required this.song});

  final SubsonicSong song;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final artist = songArtistText(song);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: HoomyDimens.listTitleFontSize,
            color: palette.playing,
          ),
        ),
        if (artist != null)
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: HoomyDimens.listSubtitleFontSize,
              color: palette.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// 迷你播放条上的图标按钮：直角、44dp 点击区，尺寸不与条高冲突。
class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        color: palette.textPrimary,
        iconSize: 22,
        padding: EdgeInsets.zero,
        icon: Icon(icon),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import 'duration_text.dart';
import 'hoomy_list_row.dart';
import 'song_secondary_text.dart';
import 'star_button.dart';

/// 歌曲行：标题 + 「歌手 - 专辑」+ 时长 + 收藏星标。
///
/// 行本身是 [HoomyListRow]：60dp、直角、按下整行变蓝且文字图标变白；
/// **不带封面缩略图**（`CONTEXT.md`「列表行」）。
///
/// [trackNumber] 非空时在行首显示音轨号（专辑详情用它，票据 14）；服务端没给
/// 音轨号就不占位，而不是编一个序号 —— 那是 metadata 里的事实。
///
/// 星标是 [StarButton.inRow]：乐观更新、失败回滚、同目标互斥与按压上色
/// 都封在它里面，本行只把时长与星标摆到行尾。
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.highlighted = false,
    this.trackNumber,
  });

  final SubsonicSong song;
  final VoidCallback? onTap;

  /// 是否是当前播放的曲目：标题用播放态红标出。
  final bool highlighted;

  /// 音轨号；null 表示不显示。
  final int? trackNumber;

  @override
  Widget build(BuildContext context) {
    final durationText = formatMetadataDuration(song.durationSec);
    final trackNumber = this.trackNumber;
    return HoomyListRow(
      title: song.title,
      subtitle: songSecondaryText(song),
      onTap: onTap,
      highlighted: highlighted,
      leadingBuilder: trackNumber == null
          ? null
          : (state) => SizedBox(
              width: _trackNumberWidth,
              child: Text(
                '$trackNumber',
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  color: state.foreground,
                ),
              ),
            ),
      trailing: (state) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (durationText != null)
            Text(
              durationText,
              style: TextStyle(
                fontSize: HoomyDimens.listSubtitleFontSize,
                fontWeight: FontWeight.bold,
                color: state.foreground,
              ),
            ),
          StarButton.inRow(
            target: songStar(song.id),
            starred: song.isStarred,
            state: state,
          ),
        ],
      ),
    );
  }
}

/// 音轨号列的固定宽度：两位数也放得下，标题不会随位数左右跳。
const _trackNumberWidth = 28.0;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import 'hoomy_list_row.dart';
import 'song_secondary_text.dart';

/// 歌曲行：标题 + 「歌手 - 专辑」+ 时长 + 收藏星标。
///
/// 行本身是 [HoomyListRow]：60dp、直角、按下整行变蓝且文字图标变白；
/// **不带封面缩略图**（`CONTEXT.md`「列表行」）。
class SongTile extends ConsumerStatefulWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.highlighted = false,
  });

  final SubsonicSong song;
  final VoidCallback? onTap;

  /// 是否是当前播放的曲目：标题用播放态红标出。
  final bool highlighted;

  @override
  ConsumerState<SongTile> createState() => _SongTileState();
}

class _SongTileState extends ConsumerState<SongTile> {
  bool _toggling = false;
  bool? _localStarred;

  bool get _effectiveStarred => _localStarred ?? widget.song.isStarred;

  Future<void> _toggleStar() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    final starRepository = ref.read(starRepositoryProvider);
    final starred = !_effectiveStarred;
    try {
      await starRepository?.setStarred(
        songId: widget.song.id,
        starred: starred,
      );
      // 本地乐观更新；列表页下次刷新拿到服务端状态。
      setState(() => _localStarred = starred);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final palette = HoomyPalette.of(context);
    final duration = song.durationSec;
    return HoomyListRow(
      title: song.title,
      subtitle: songSecondaryText(song),
      onTap: widget.onTap,
      highlighted: widget.highlighted,
      trailing: (state) {
        // 未按下且已收藏时星标用播放红；按下时统一变白。
        final starColor = _effectiveStarred && !state.pressed
            ? palette.playing
            : state.foreground;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (duration != null)
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  fontWeight: FontWeight.bold,
                  color: state.foreground,
                ),
              ),
            IconButton(
              onPressed: _toggleStar,
              color: starColor,
              icon: Icon(_effectiveStarred ? Icons.star : Icons.star_border),
            ),
          ],
        );
      },
    );
  }
}

String _formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

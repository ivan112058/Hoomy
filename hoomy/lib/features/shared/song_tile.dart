import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';

/// 歌曲行：标题 + 歌手·专辑 + 时长 + 收藏星标。
class SongTile extends ConsumerStatefulWidget {
  const SongTile({super.key, required this.song, this.onTap});

  final SubsonicSong song;
  final VoidCallback? onTap;

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
    final favorites = ref.read(favoriteRepositoryProvider);
    final starred = !_effectiveStarred;
    try {
      await favorites?.setStarred(songId: widget.song.id, starred: starred);
      // 本地乐观更新；列表页下次刷新拿到服务端状态。
      setState(() => _localStarred = starred);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final theme = Theme.of(context);
    return ListTile(
      onTap: widget.onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (song.artist != null && song.artist!.isNotEmpty) song.artist!,
          if (song.album != null && song.album!.isNotEmpty) song.album!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.durationSec != null)
            Text(
              _formatDuration(song.durationSec!),
              style: theme.textTheme.bodySmall,
            ),
          IconButton(
            onPressed: _toggleStar,
            icon: Icon(
              _effectiveStarred ? Icons.star : Icons.star_border,
              color: _effectiveStarred ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

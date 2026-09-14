import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../playlists/playlists_page.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import 'genre_list_page.dart';
import 'starred_songs_page.dart';

/// 更多 Tab：播放列表、风格、我喜欢的歌曲；左上角为设置入口。
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageScaffold(
      title: '更多',
      leading: IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: '设置',
        // TODO(设置页): 设置入口尚未实现，包含封面缓存清除、退出登录。
        onPressed: null,
      ),
      body: ListView(
        children: [
          _MoreTile(
            icon: Icons.queue_music_outlined,
            title: '播放列表',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlaylistsPage()),
            ),
          ),
          _MoreTile(
            icon: Icons.category_outlined,
            title: '风格',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GenreListPage()),
            ),
          ),
          _MoreTile(
            icon: Icons.star_outline,
            title: '我喜欢的歌曲',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StarredSongsPage()),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Hoomy · 局域网 NAS 音乐播放器',
              style: theme.textTheme.bodySmall?.copyWith(
                color: HoomyPalette.of(context).textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoomyListRow(
      title: title,
      leading: Icon(icon),
      onTap: onTap,
      trailing: (_) => const Icon(Icons.chevron_right),
    );
  }
}

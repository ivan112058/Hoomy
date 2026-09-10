import 'package:flutter/material.dart';

import '../shared/async_view.dart';
import 'genre_list_page.dart';
import 'starred_songs_page.dart';

/// 更多 Tab：风格、我喜欢的歌曲；左上角为设置入口。
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
          const Divider(height: 0.67),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Hoomy · 局域网 NAS 音乐播放器',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.dividerColor),
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
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

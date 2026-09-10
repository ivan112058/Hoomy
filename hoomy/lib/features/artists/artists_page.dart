import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';

/// 艺术家 Tab：全库歌手列表。
class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistRepository = ref.watch(artistRepositoryProvider);
    if (artistRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '艺术家',
      body: AsyncView(
        load: artistRepository.getArtists,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, artists) => ListView.separated(
          itemCount: artists.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, i) {
            final artist = artists[i];
            return HoomyListRow(
              title: artist.name,
              trailing: (state) => Text(
                '${artist.albumCount ?? 0} 张专辑',
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  color: state.foreground,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';

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
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) {
            final artist = artists[i];
            return ListTile(
              title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('${artist.albumCount ?? 0} 张专辑'),
            );
          },
        ),
      ),
    );
  }
}

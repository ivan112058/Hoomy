import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';

/// 艺术家 Tab：全库艺术家列表。
class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistRepositoryProvider);
    if (artists == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '艺术家',
      body: AsyncView(
        load: artists.getArtists,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) {
            final artist = list[i];
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/cover_art.dart';

/// 专辑 Tab：3 列封面网格（Smartisan 相册式布局）。
class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumRepositoryProvider);
    if (albums == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '专辑',
      body: AsyncView(
        load: albums.getAllAlbums,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, list) => GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.82,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final album = list[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: CoverArt(
                    coverArtId: album.coverArtId,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        album.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).dividerColor,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

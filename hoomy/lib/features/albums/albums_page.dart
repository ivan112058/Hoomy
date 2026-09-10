import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';
import '../shared/cover_art.dart';

/// 专辑 Tab：固定 3 列封面网格，封面 1:1（`CONTEXT.md`「专辑网格」）。
class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumRepository = ref.watch(albumRepositoryProvider);
    if (albumRepository == null) return const SizedBox.shrink();
    final palette = HoomyPalette.of(context);
    return PageScaffold(
      title: '专辑',
      body: AsyncView(
        load: albumRepository.getAllAlbums,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, albums) => LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: HoomyDimens.albumGridColumns,
              childAspectRatio: _cellAspectRatio(constraints.maxWidth),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) {
              final album = albums[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CoverArt(coverArtId: album.coverArtId),
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
                          style: TextStyle(
                            fontSize: HoomyDimens.listSubtitleFontSize,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          album.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: HoomyDimens.listSubtitleFontSize,
                            color: palette.textSecondary,
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
      ),
    );
  }
}

/// 封面下方两行文字的预留高度：6dp 间距 + 两行 13sp 文本的余量。
const _captionHeight = 46.0;

/// 列数固定为 3，封面因此始终 1:1；单元高出的部分留给封面下方的两行文字。
///
/// 用实际可用宽度反推单元宽高比，窄屏（如 320dp）与宽屏都不会挤压封面。
double _cellAspectRatio(double maxWidth) {
  const padding = 4.0 * 2;
  const spacing = 4.0 * (HoomyDimens.albumGridColumns - 1);
  final cover =
      (maxWidth - padding - spacing) / HoomyDimens.albumGridColumns;
  return cover / (cover + _captionHeight);
}

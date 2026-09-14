import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import '../shared/album_grid_cell.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import 'album_detail_page.dart';

/// 专辑 Tab：固定 3 列封面网格、封面 1:1（`CONTEXT.md`「专辑网格」），
/// 按专辑名拼音首字母分组并带 A–Z 快捷栏。
///
/// 点单元进专辑详情（票据 14）；网格单元的几何与部件在 [AlbumGridCell]，
/// 与歌手详情的专辑网格共用。
class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumRepository = ref.watch(albumRepositoryProvider);
    if (albumRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '专辑',
      body: AsyncView(
        load: albumRepository.getAllAlbums,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, albums) => LayoutBuilder(
          builder: (context, constraints) => AlphabetSectionedGrid<SubsonicAlbum>(
            sections: buildAlphabetSections(albums, keyOf: (album) => album.name),
            columns: HoomyDimens.albumGridColumns,
            cellExtent: albumGridCellExtent(constraints.maxWidth),
            spacing: kAlbumGridSpacing,
            itemBuilder: (context, album, _) => AlbumGridCell(
              album: album,
              onTap: () => openAlbumDetail(context, album),
            ),
          ),
        ),
      ),
    );
  }
}

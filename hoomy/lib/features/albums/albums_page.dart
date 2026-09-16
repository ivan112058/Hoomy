import 'package:flutter/material.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/session/session_providers.dart';
import '../../data/subsonic/models.dart';
import '../shared/album_grid_cell.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import 'album_detail_page.dart';

/// 专辑 Tab：固定 3 列封面网格、封面 1:1（`CONTEXT.md`「专辑网格」），
/// 按专辑名拼音首字母分组并带 A–Z 快捷栏。
///
/// 曲库从**会话**取（ADR-0015 决策 1），以异步值订阅；页面不持有取数回调，
/// 也没有「没有数据源」的分支 —— 载入、失败重试与空态都由 [AsyncValueView]
/// 呈现。点单元进专辑详情（票据 14）。
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '专辑',
      body: AsyncValueView(
        provider: allAlbumsProvider,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/cover_art.dart';
import '../shared/star_button.dart';

/// 专辑 Tab：固定 3 列封面网格、封面 1:1（`CONTEXT.md`「专辑网格」），
/// 按专辑名拼音首字母分组并带 A–Z 快捷栏。
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
          builder: (context, constraints) =>
              AlphabetSectionedGrid<SubsonicAlbum>(
            sections: buildAlphabetSections(albums, keyOf: (album) => album.name),
            columns: HoomyDimens.albumGridColumns,
            cellExtent: _cellExtent(constraints.maxWidth),
            spacing: _spacing,
            itemBuilder: (context, album, _) => _AlbumCell(album: album),
          ),
        ),
      ),
    );
  }
}

/// 网格间距：行距、列距与左右内边距统一一个值。
const _spacing = 4.0;

/// 封面下方两行文字的预留高度：6dp 间距 + 两行 13sp 文本的余量。
const _captionHeight = 46.0;

/// 列数固定为 3，封面因此始终 1:1；单元高出的部分留给封面下方的两行文字。
///
/// 用实际可用宽度反推单元高度，窄屏（如 320dp）与宽屏都不会挤压封面。
double _cellExtent(double maxWidth) {
  final available = maxWidth - _spacing * (HoomyDimens.albumGridColumns + 1);
  final cover = available / HoomyDimens.albumGridColumns;
  return cover + _captionHeight;
}

/// 一个网格单元：1:1 封面 + 专辑名 + 歌手名。
class _AlbumCell extends StatelessWidget {
  const _AlbumCell({required this.album});

  final SubsonicAlbum album;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: CoverArt(coverArtId: album.coverArtId),
              ),
              // 收藏入口盖在封面右上角：格子太窄，塞进两行文字里会挤压专辑名。
              Positioned(top: 0, right: 0, child: _CoverStar(album: album)),
            ],
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
  }
}

/// 封面右上角的收藏星标：半透明方底保证在任何封面颜色上都看得清。
class _CoverStar extends StatelessWidget {
  const _CoverStar({required this.album});

  final SubsonicAlbum album;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: ColoredBox(
        color: palette.pageBackground.withValues(alpha: 0.72),
        child: StarButton(
          target: albumStar(album.id),
          starred: album.isStarred,
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        ),
      ),
    );
  }
}

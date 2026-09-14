import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import 'cover_art.dart';
import 'star_button.dart';

/// 专辑网格的共享几何与单元部件。
///
/// 专辑 Tab 的字母分组网格与歌手详情页的专辑网格是同一个东西：固定
/// [HoomyDimens.albumGridColumns] 列、封面 1:1、单元下方两行文字。
/// 几何算式与单元部件放在这里，两处不再各写一份、各自漂移。

/// 网格间距：行距、列距与左右内边距统一一个值。
const kAlbumGridSpacing = 4.0;

/// 封面下方两行文字的预留高度：6dp 间距 + 两行 13sp 文本的余量。
const _captionHeight = 46.0;

/// 列数固定为 3，封面因此始终 1:1；单元高出的部分留给封面下方的两行文字。
///
/// 用实际可用宽度反推单元高度，窄屏（如 320dp）与宽屏都不会挤压封面。
double albumGridCellExtent(double maxWidth) {
  final available =
      maxWidth - kAlbumGridSpacing * (HoomyDimens.albumGridColumns + 1);
  final cover = available / HoomyDimens.albumGridColumns;
  return cover + _captionHeight;
}

/// 一个网格单元：1:1 封面 + 专辑名 + 歌手名。
///
/// 点单元进专辑详情（[onTap] 为 null 时不可进，仍可收藏）。封面右上角的收藏
/// 星标是票据 12 的入口：点它只收藏，不会连带进详情 —— 内层手势赢得竞技场。
class AlbumGridCell extends StatelessWidget {
  const AlbumGridCell({super.key, required this.album, this.onTap});

  final SubsonicAlbum album;

  /// 点单元的回调；网格的调用方据此推入专辑详情。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(child: CoverArt(coverArtId: album.coverArtId)),
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
      ),
    );
  }
}

/// 专辑网格的 sliver 形态：固定列数、固定单元高度，点单元进详情。
///
/// 专辑 Tab 按字母分组，用它的是 `AlphabetSectionedGrid`；歌手详情这类
/// 不分组的场景直接用这个，免得再抄一遍网格委托。
class SliverAlbumGrid extends StatelessWidget {
  const SliverAlbumGrid({
    super.key,
    required this.albums,
    required this.cellExtent,
    this.onTap,
  });

  final List<SubsonicAlbum> albums;

  /// 单元高度；由调用方按可用宽度用 [albumGridCellExtent] 算好。
  final double cellExtent;

  final void Function(SubsonicAlbum album)? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: kAlbumGridSpacing),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: HoomyDimens.albumGridColumns,
          mainAxisExtent: cellExtent,
          mainAxisSpacing: kAlbumGridSpacing,
          crossAxisSpacing: kAlbumGridSpacing,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => AlbumGridCell(
            album: albums[i],
            onTap: onTap == null ? null : () => onTap(albums[i]),
          ),
          childCount: albums.length,
        ),
      ),
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

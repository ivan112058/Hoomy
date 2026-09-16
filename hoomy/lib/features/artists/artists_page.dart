import 'package:flutter/material.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/session/session_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/star_button.dart';
import 'artist_detail_page.dart';

/// 艺术家 Tab：全库歌手按拼音首字母分组的列表。
///
/// 曲库从**会话**取（ADR-0015 决策 1），以异步值订阅；页面不持有取数回调，
/// 也没有「没有数据源」的分支 —— 载入、失败重试与空态都由 [AsyncValueView]
/// 呈现。行尾给专辑数与收藏星标；点行进入歌手详情（票据 14）。
class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '艺术家',
      body: AsyncValueView(
        provider: allArtistsProvider,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, artists) => AlphabetSectionedList<SubsonicArtist>(
          sections: buildAlphabetSections(artists, keyOf: (artist) => artist.name),
          itemExtent: kHoomyListRowExtent,
          itemBuilder: (context, artist, _) => HoomyDividedRow(
            child: HoomyListRow(
              title: artist.name,
              onTap: () => openArtistDetail(context, artist),
              trailing: (state) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${artist.albumCount ?? 0} 张专辑',
                    style: TextStyle(
                      fontSize: HoomyDimens.listSubtitleFontSize,
                      color: state.foreground,
                    ),
                  ),
                  StarButton.inRow(
                    target: artistStar(artist.id),
                    starred: artist.isStarred,
                    state: state,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

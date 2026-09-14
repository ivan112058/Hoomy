import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/star_button.dart';

/// 艺术家 Tab：全库歌手按拼音首字母分组的列表。
///
/// 行尾给专辑数与收藏星标；点行进入详情属票据 14，本页暂不接线。
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
        itemBuilder: (context, artists) => AlphabetSectionedList<SubsonicArtist>(
          sections: buildAlphabetSections(artists, keyOf: (artist) => artist.name),
          itemExtent: kHoomyListRowExtent,
          itemBuilder: (context, artist, _) => HoomyDividedRow(
            child: HoomyListRow(
              title: artist.name,
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

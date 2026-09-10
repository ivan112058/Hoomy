import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alphabet/alphabet.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import '../player/playback_listenable.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/play_song.dart';
import '../shared/song_tile.dart';
import 'song_search.dart';

/// 歌曲 Tab：全库歌曲的分组列表 + 本地搜索。
///
/// 曲库经 `SongRepository` 以 `search3` 空 query 分页取全量（ADR-0005），
/// 不再有硬上限。响应不含总数，因此界面也不显示条数或页码。
class SongsPage extends ConsumerWidget {
  const SongsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songRepository = ref.watch(songRepositoryProvider);
    if (songRepository == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '歌曲',
      body: AsyncView(
        load: songRepository.getAllSongs,
        emptyMessage: '曲库是空的',
        itemBuilder: (context, songs) => _SongsBody(songs: songs),
      ),
    );
  }
}

/// 搜索框 + 字母分组列表。
///
/// 过滤只发生在 [songs] 这份已取回的全量数据上（ADR-0005），不发起请求，
/// 所以输入即时生效；清空搜索词即回到完整分组列表。
class _SongsBody extends ConsumerStatefulWidget {
  const _SongsBody({required this.songs});

  final List<SubsonicSong> songs;

  @override
  ConsumerState<_SongsBody> createState() => _SongsBodyState();
}

class _SongsBodyState extends ConsumerState<_SongsBody> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 点一首歌：以**当前可见列表**为播放队列，从这一首开始播。
  ///
  /// 搜索过滤后点歌时，队列就是过滤后的结果 —— 用户看到的上下文是什么，
  /// 连续播放的上下文就是什么（spec 用户故事 24）。
  void _play(List<SubsonicSong> visible, SubsonicSong song) =>
      playSongFromList(ref, visible, song);

  @override
  Widget build(BuildContext context) {
    final matched = filterSongsByQuery(widget.songs, _query);
    final sections = buildAlphabetSections(
      matched,
      keyOf: (song) => song.title,
    );

    return Column(
      children: [
        _SearchField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
        ),
        Expanded(
          child: matched.isEmpty
              ? const Center(child: Text('没有匹配的歌曲'))
              // 只在换歌时重建列表；进度每 ~200ms 的通知不会带累它。
              : CurrentSongIdBuilder(
                  builder: (context, currentSongId) =>
                      AlphabetSectionedList<SubsonicSong>(
                        sections: sections,
                        itemExtent: kHoomyListRowExtent,
                        itemBuilder: (context, song, _) => HoomyDividedRow(
                          child: SongTile(
                            song: song,
                            highlighted: song.id == currentSongId,
                            onTap: () => _play(matched, song),
                          ),
                        ),
                      ),
                ),
        ),
      ],
    );
  }
}

/// 搜索框：输入即过滤本地数据，有词时给出清空入口。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索歌曲',
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

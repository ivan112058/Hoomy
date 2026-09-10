import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alphabet/alphabet.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/subsonic/models.dart';
import '../shared/alphabet_sectioned_view.dart';
import '../shared/async_view.dart';
import '../shared/hoomy_list_row.dart';
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
class _SongsBody extends StatefulWidget {
  const _SongsBody({required this.songs});

  final List<SubsonicSong> songs;

  @override
  State<_SongsBody> createState() => _SongsBodyState();
}

class _SongsBodyState extends State<_SongsBody> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = filterSongsByQuery(widget.songs, _query);
    final sections = buildAlphabetSections(matched, keyOf: (song) => song.title);

    return Column(
      children: [
        _SearchField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
        ),
        Expanded(
          child: matched.isEmpty
              ? const Center(child: Text('没有匹配的歌曲'))
              : AlphabetSectionedList<SubsonicSong>(
                  sections: sections,
                  itemExtent: kHoomyListRowExtent,
                  itemBuilder: (context, song, _) =>
                      HoomyDividedRow(child: SongTile(song: song)),
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

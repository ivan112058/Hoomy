import '../../data/subsonic/models.dart';

/// 歌曲的本地搜索键：歌名、歌手、专辑拼成一个串。
///
/// 拼接成一个串，是为了让过滤只做一次子串匹配；命中任意一项即算匹配。
/// 缺失的字段不参与拼接，不留下多余空白。
String songSearchText(SubsonicSong song) => [song.title, song.artist, song.album]
    .whereType<String>()
    .where((part) => part.isNotEmpty)
    .join(' ');

/// 在已取回的歌曲里按 [query] 做本地子串过滤，大小写不敏感。
///
/// [query] 去空白后为空时原样返回 [songs]。纯内存操作，不触发任何
/// 网络请求（ADR-0005）。
List<SubsonicSong> filterSongsByQuery(List<SubsonicSong> songs, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return songs;

  return songs
      .where((song) => songSearchText(song).toLowerCase().contains(needle))
      .toList();
}

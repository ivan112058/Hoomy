import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';
import 'paged_fetch.dart';

/// 风格取数：曲库里的流派分组与其曲目。
class GenreRepository {
  GenreRepository(this._client);

  final SubsonicClient _client;

  /// 曲库里的全部风格，含各自的曲目数与专辑数。
  ///
  /// 丢掉没有 `value` 的空名条目：`getSongsByGenre` 的 `genre` 是必填参数，
  /// 空名风格点进去只能换来一次服务端错误（解析对字段缺失容错，但不假装它可用）。
  Future<List<SubsonicGenre>> getGenres() async {
    final genres = await _client.getGenres();
    return [
      for (final genre in genres)
        if (genre.name.isNotEmpty) genre,
    ];
  }

  /// 该风格下的全部歌曲。
  ///
  /// 与全库歌曲同理：响应不带总数，按 offset 翻页直到短页或空页。
  Future<List<SubsonicSong>> getSongs(String genre) => fetchAllPages(
    fetchPage: (offset) => _client.getSongsByGenre(
      genre: genre,
      count: kListPageSize,
      offset: offset,
    ),
    idOf: (song) => song.id,
  );
}

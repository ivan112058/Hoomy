import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';
import 'paged_fetch.dart';

/// 歌曲取数：对上层暴露歌曲领域模型，不暴露协议响应结构。
///
/// 全库歌曲走 `search3` 空 query 分页（ADR-0005）。分页只是传输手段，
/// 不是 UI 概念 —— `searchResult3` 不返回总数，调用方也无从得知。
class SongRepository {
  SongRepository(this._client);

  final SubsonicClient _client;

  /// 曲库里的全部歌曲，按服务端自然顺序，且不含重复项。
  ///
  /// 循环递增 `songOffset`，直到出现短页或空页为止；重叠页按 id 去重，
  /// 服务端忽略 offset 时在整页重复处终止（防死循环）。
  Future<List<SubsonicSong>> getAllSongs() => fetchAllPages(
        fetchPage: (offset) => _client.search3Songs(
          songCount: kListPageSize,
          songOffset: offset,
        ),
        idOf: (song) => song.id,
      );
}

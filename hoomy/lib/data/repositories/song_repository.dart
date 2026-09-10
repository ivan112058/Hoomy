import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 歌曲取数：对上层暴露歌曲领域模型，不暴露协议响应结构。
///
/// 全库歌曲走 `search3` 空 query 分页（ADR-0005）。分页只是传输手段，
/// 不是 UI 概念 —— `searchResult3` 不返回总数，调用方也无从得知。
class SongRepository {
  SongRepository(this._client);

  final SubsonicClient _client;

  /// 单页条数。Navidrome 对 `search3` 没有硬上限；500 是实测曲库下两次请求的取值。
  static const pageSize = 500;

  /// 曲库里的全部歌曲，按服务端自然顺序。
  ///
  /// 循环递增 `songOffset`，直到出现短页或空页为止。服务端若返回重叠页，
  /// 按 id 去重且保留首次出现的顺序；若服务端忽略 `songOffset`（每页都相同），
  /// 在整页重复时终止，避免死循环。因此结果里不会有重复歌曲。
  Future<List<SubsonicSong>> getAllSongs() async {
    final songs = <SubsonicSong>[];
    final seenIds = <String>{};
    var offset = 0;

    while (true) {
      final page = await _client.search3Songs(
        songCount: pageSize,
        songOffset: offset,
      );
      var added = 0;
      for (final song in page) {
        if (seenIds.add(song.id)) {
          songs.add(song);
          added++;
        }
      }
      // 空页或短页：已经到达末尾。
      if (page.length < pageSize) break;
      // 防御：整页都是重复项说明服务端没有按 offset 翻页，继续下去会死循环。
      if (added == 0) break;
      offset += pageSize;
    }

    return songs;
  }
}

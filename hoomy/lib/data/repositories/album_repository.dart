import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 专辑取数：对上层暴露专辑领域模型（含曲目）。
class AlbumRepository {
  AlbumRepository(this._client);

  final SubsonicClient _client;

  /// `getAlbumList2` 的 `size` 上限为 500（服务端硬编码），即单页条数。
  static const pageSize = 500;

  /// 曲库里的全部专辑，按 `alphabeticalByName` 自然顺序。
  ///
  /// 与歌曲列表同理：`getAlbumList2` 的响应也不带总数，只能靠翻页取全量。
  /// 按 id 去重；服务端忽略 offset 时在整页重复处终止。
  Future<List<SubsonicAlbum>> getAllAlbums() async {
    final albums = <SubsonicAlbum>[];
    final seenIds = <String>{};
    var offset = 0;

    while (true) {
      final page = await _client.getAlbumList2(size: pageSize, offset: offset);
      var added = 0;
      for (final album in page) {
        if (seenIds.add(album.id)) {
          albums.add(album);
          added++;
        }
      }
      if (page.length < pageSize) break;
      if (added == 0) break;
      offset += pageSize;
    }

    return albums;
  }

  /// 专辑详情：含曲目列表。
  Future<SubsonicAlbum> getAlbum(String id) => _client.getAlbum(id);
}

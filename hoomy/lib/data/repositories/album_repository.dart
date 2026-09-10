import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';
import 'paged_fetch.dart';

/// 专辑取数：对上层暴露专辑领域模型（含曲目）。
class AlbumRepository {
  AlbumRepository(this._client);

  final SubsonicClient _client;

  /// `getAlbumList2` 的 `size` 上限为 500（服务端硬编码），即单页条数。
  static const pageSize = 500;

  /// 曲库里的全部专辑，按 `alphabeticalByName` 自然顺序，且不含重复项。
  ///
  /// 与歌曲列表同理：响应不带总数，只能靠翻页取全量。
  Future<List<SubsonicAlbum>> getAllAlbums() => fetchAllPages(
        pageSize: pageSize,
        fetchPage: (offset) =>
            _client.getAlbumList2(size: pageSize, offset: offset),
        idOf: (album) => album.id,
      );

  /// 专辑详情：含曲目列表。
  Future<SubsonicAlbum> getAlbum(String id) => _client.getAlbum(id);
}

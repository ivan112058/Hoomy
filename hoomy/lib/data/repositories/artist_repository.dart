import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 歌手取数：对上层暴露歌手领域模型（含专辑与曲目）。
class ArtistRepository {
  ArtistRepository(this._client);

  final SubsonicClient _client;

  /// 按演唱/演奏者聚合的歌手列表（`getArtists` 的 index 分组打平）。
  Future<List<SubsonicArtist>> getArtists() => _client.getArtists();

  /// 歌手详情：含该歌手的专辑列表。
  Future<SubsonicArtist> getArtist(String id) => _client.getArtist(id);

  /// 该歌手的全部歌曲。
  ///
  /// Subsonic 没有「按歌手取全部歌曲」的端点：`getArtist` 只返回专辑，
  /// 因此逐张 `getAlbum` 取曲目后按专辑顺序打平，并按 id 去重。
  Future<List<SubsonicSong>> getArtistSongs(String artistId) async {
    final artist = await _client.getArtist(artistId);
    final songs = <SubsonicSong>[];
    final seenIds = <String>{};

    for (final album in artist.albums) {
      final detail = await _client.getAlbum(album.id);
      for (final song in detail.songs) {
        if (seenIds.add(song.id)) songs.add(song);
      }
    }

    return songs;
  }
}

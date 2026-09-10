import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 歌单取数：服务端歌单（MVP 只读）。
class PlaylistRepository {
  PlaylistRepository(this._client);

  final SubsonicClient _client;

  Future<List<SubsonicPlaylist>> getPlaylists() => _client.getPlaylists();

  /// 歌单详情：含曲目列表。
  Future<SubsonicPlaylist> getPlaylist(String id) => _client.getPlaylist(id);
}

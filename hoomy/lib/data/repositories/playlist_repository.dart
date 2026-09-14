import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 播放列表取数：服务端保存的播放列表（MVP 只读）。
class PlaylistRepository {
  PlaylistRepository(this._client);

  final SubsonicClient _client;

  Future<List<SubsonicPlaylist>> getPlaylists() => _client.getPlaylists();

  /// 播放列表详情：含曲目列表。
  Future<SubsonicPlaylist> getPlaylist(String id) => _client.getPlaylist(id);
}

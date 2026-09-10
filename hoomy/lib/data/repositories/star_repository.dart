import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 收藏（Star）取数：收藏状态保存在服务端，跨设备同步。
///
/// 写路径的乐观更新与失败回滚由界面层负责（票据 12），本类只做协议调用。
class StarRepository {
  StarRepository(this._client);

  final SubsonicClient _client;

  /// 「我喜欢的歌曲」：服务端已 star 的歌曲。
  Future<List<SubsonicSong>> getStarredSongs() => _client.getStarredSongs();

  /// 收藏/取消收藏（songId / albumId / artistId 三选一）。
  Future<void> setStarred({
    String? songId,
    String? albumId,
    String? artistId,
    required bool starred,
  }) =>
      _client.setStarred(
        songId: songId,
        albumId: albumId,
        artistId: artistId,
        starred: starred,
      );
}

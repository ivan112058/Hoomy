import '../star/star_target.dart';
import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 收藏（Star）取数：收藏状态保存在服务端，跨设备同步。
///
/// 写路径的乐观更新与失败回滚由界面层的 `StarStore` 负责（票据 12），
/// 本类只把领域目标翻成协议参数。
class StarRepository {
  StarRepository(this._client);

  final SubsonicClient _client;

  /// 「我喜欢的歌曲」：服务端已 star 的歌曲。
  Future<List<SubsonicSong>> getStarredSongs() => _client.getStarredSongs();

  /// 收藏/取消收藏 [target]（歌曲／专辑／歌手三选一）。
  Future<void> setStarred(StarTarget target, {required bool starred}) {
    // `star`/`unstar` 的歌曲参数名是 `id`，专辑/歌手各自一个参数；
    // 翻译只在这里做一次，上层不必再关心三个互斥的可空字符串。
    final (songId, albumId, artistId) = switch (target.kind) {
      StarKind.song => (target.id, null, null),
      StarKind.album => (null, target.id, null),
      StarKind.artist => (null, null, target.id),
    };
    return _client.setStarred(
      songId: songId,
      albumId: albumId,
      artistId: artistId,
      starred: starred,
    );
  }
}

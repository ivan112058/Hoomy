import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 歌手详情的数据：歌手本身（含专辑）与打平去重后的全部歌曲。
class ArtistDetail {
  const ArtistDetail({required this.artist, required this.songs});

  final SubsonicArtist artist;

  /// 该歌手全部专辑的曲目，按专辑顺序打平、按 id 去重。
  final List<SubsonicSong> songs;
}

/// 歌手取数：对上层暴露歌手领域模型（含专辑与曲目）。
class ArtistRepository {
  ArtistRepository(this._client);

  final SubsonicClient _client;

  /// 按演唱/演奏者聚合的歌手列表（`getArtists` 的 index 分组打平）。
  Future<List<SubsonicArtist>> getArtists() => _client.getArtists();

  /// 歌手详情：该歌手的专辑与全部歌曲，**一次**取回。
  ///
  /// 详情页只需要这一个方法。取数要点：`getArtist` 只返回专辑，Subsonic 也没有
  /// 「按歌手取全部歌曲」的端点，因此逐张 `getAlbum` 取曲目后按专辑顺序打平、
  /// 按 id 去重。页面若自己先取专辑再取歌曲，会白发一次 `getArtist`。
  Future<ArtistDetail> getArtistDetail(String id) async {
    final artist = await _client.getArtist(id);
    return ArtistDetail(artist: artist, songs: await _songsOf(artist));
  }

  Future<List<SubsonicSong>> _songsOf(SubsonicArtist artist) async {
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

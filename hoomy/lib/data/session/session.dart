import 'package:dio/dio.dart';

import '../lyrics/song_lyrics.dart';
import '../repositories/album_repository.dart';
import '../repositories/artist_repository.dart';
import '../repositories/genre_repository.dart';
import '../repositories/lyrics_repository.dart';
import '../repositories/playlist_repository.dart';
import '../repositories/song_repository.dart';
import '../repositories/star_repository.dart';
import '../star/star_target.dart';
import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// 会话：一次已认证的服务器连接，取数的唯一入口（ADR-0015）。
///
/// 它只交出**领域数据**与**地址**（[Uri]），不交出协议客户端本体 —— 调用方
/// 拿不到 `SubsonicClient`，因此「怎么发请求、翻几页、怎么解析」不会漏到页面与
/// 播放层。
///
/// 分页、去重、防死循环、解析容错都在门后；调用方只说它要什么数据。
class Session {
  Session({
    required SubsonicCredentials credentials,
    required Dio transport,
  }) : _client = SubsonicClient(credentials: credentials, dio: transport);

  final SubsonicClient _client;

  // 各取数助手按需构造，持有同一个协议客户端。
  late final SongRepository _songs = SongRepository(_client);
  late final AlbumRepository _albums = AlbumRepository(_client);
  late final ArtistRepository _artists = ArtistRepository(_client);
  late final PlaylistRepository _playlists = PlaylistRepository(_client);
  late final GenreRepository _genres = GenreRepository(_client);
  late final StarRepository _stars = StarRepository(_client);
  late final LyricsRepository _lyrics = LyricsRepository(_client);

  /// 曲库里的全部歌曲（`search3` 空 query 分页取全量，ADR-0005）。
  Future<List<SubsonicSong>> allSongs() => _songs.getAllSongs();

  /// 曲库里的全部专辑。
  Future<List<SubsonicAlbum>> allAlbums() => _albums.getAllAlbums();

  /// 一张专辑的详情（含曲目）。
  Future<SubsonicAlbum> album(String id) => _albums.getAlbum(id);

  /// 曲库里的全部歌手。
  Future<List<SubsonicArtist>> allArtists() => _artists.getArtists();

  /// 一位歌手的详情（其专辑与全部歌曲）。
  Future<ArtistDetail> artistDetail(String id) => _artists.getArtistDetail(id);

  /// 服务端的歌单列表。
  Future<List<SubsonicPlaylist>> playlists() => _playlists.getPlaylists();

  /// 一个歌单的详情（含曲目）。
  Future<SubsonicPlaylist> playlist(String id) => _playlists.getPlaylist(id);

  /// 曲库里的风格列表（空名风格已丢弃）。
  Future<List<SubsonicGenre>> genres() => _genres.getGenres();

  /// 某个风格下的全部歌曲。
  Future<List<SubsonicSong>> genreSongs(String genre) => _genres.getSongs(genre);

  /// 「我喜欢的歌曲」：服务端已收藏的歌曲。
  Future<List<SubsonicSong>> starredSongs() => _stars.getStarredSongs();

  /// 一首歌的歌词；没有歌词时返回 null（界面呈现「暂无歌词」）。
  Future<SongLyrics?> lyricsFor({
    required String songId,
    String artist = '',
    String title = '',
  }) => _lyrics.lyricsFor(songId: songId, artist: artist, title: title);

  /// 收藏／取消收藏 [target]（歌曲／专辑／歌手三选一）。
  Future<void> setStarred(StarTarget target, {required bool starred}) =>
      _stars.setStarred(target, starred: starred);

  /// 某首歌的播放地址。纯拼接，不发请求。
  Uri streamUri(String songId) => _client.streamUri(songId);

  /// 某张封面的地址。纯拼接，不发请求。
  Uri coverArtUri(String coverArtId, {int? size}) =>
      _client.coverArtUri(coverArtId, size: size);
}

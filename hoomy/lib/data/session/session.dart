import 'package:dio/dio.dart';

import '../lyrics/song_lyrics.dart';
import '../star/star_target.dart';
import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';
import 'paged_fetch.dart';

/// 歌手详情的数据：歌手本身（含专辑）与打平去重后的全部歌曲。
class ArtistDetail {
  const ArtistDetail({required this.artist, required this.songs});

  final SubsonicArtist artist;

  /// 该歌手全部专辑的曲目，按专辑顺序打平、按 id 去重。
  final List<SubsonicSong> songs;
}

/// 会话：一次已认证的服务器连接，取数的唯一入口（ADR-0015）。
///
/// 它只交出**领域数据**与**地址**（[Uri]），不交出协议客户端本体 —— 调用方
/// 拿不到 `SubsonicClient`，因此「怎么发请求、翻几页、怎么解析」不会漏到页面与
/// 播放层。
///
/// 取数逻辑就长在这里，不再另立按实体切分的转发层：分页循环、去重、防死循环、
/// 歌手详情的多请求合并、歌词缓存都在门后。调用方只说它要什么数据。
class Session {
  Session({
    required SubsonicCredentials credentials,
    required Dio transport,
  }) : _client = SubsonicClient(credentials: credentials, dio: transport);

  final SubsonicClient _client;

  /// 曲库里的全部歌曲（`search3` 空 query 分页取全量，ADR-0005）。
  ///
  /// 循环递增 `songOffset`，直到出现短页或空页为止；重叠页按 id 去重，
  /// 服务端忽略 offset 时在整页重复处终止（防死循环）。
  Future<List<SubsonicSong>> allSongs() => fetchAllPages(
        fetchPage: (offset) => _client.search3Songs(
          songCount: kListPageSize,
          songOffset: offset,
        ),
        idOf: (song) => song.id,
      );

  /// 曲库里的全部专辑，按 `alphabeticalByName` 自然顺序，且不含重复项。
  Future<List<SubsonicAlbum>> allAlbums() => fetchAllPages(
        fetchPage: (offset) => _client.getAlbumList2(
          size: kListPageSize,
          offset: offset,
        ),
        idOf: (album) => album.id,
      );

  /// 一张专辑的详情（含曲目）。
  Future<SubsonicAlbum> album(String id) => _client.getAlbum(id);

  /// 曲库里的全部歌手（`getArtists` 的 index 分组打平）。
  Future<List<SubsonicArtist>> allArtists() => _client.getArtists();

  /// 一位歌手的详情（其专辑与全部歌曲），**一次**取回。
  ///
  /// `getArtist` 只返回专辑，Subsonic 也没有「按歌手取全部歌曲」的端点，因此
  /// 逐张 `getAlbum` 取曲目后按专辑顺序打平、按 id 去重。页面若自己先取专辑再
  /// 取歌曲，会白发一次 `getArtist`。
  Future<ArtistDetail> artistDetail(String id) async {
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

  /// 服务端的播放列表。
  Future<List<SubsonicPlaylist>> playlists() => _client.getPlaylists();

  /// 一个播放列表的详情（含曲目）。
  Future<SubsonicPlaylist> playlist(String id) => _client.getPlaylist(id);

  /// 曲库里的风格列表（空名风格已丢弃）。
  ///
  /// 丢掉没有 `value` 的空名条目：`getSongsByGenre` 的 `genre` 是必填参数，
  /// 空名风格点进去只能换来一次服务端错误。
  Future<List<SubsonicGenre>> genres() async {
    final genres = await _client.getGenres();
    return [
      for (final genre in genres)
        if (genre.name.isNotEmpty) genre,
    ];
  }

  /// 某个风格下的全部歌曲，按 offset 翻页直到短页或空页。
  Future<List<SubsonicSong>> genreSongs(String genre) => fetchAllPages(
        fetchPage: (offset) => _client.getSongsByGenre(
          genre: genre,
          count: kListPageSize,
          offset: offset,
        ),
        idOf: (song) => song.id,
      );

  /// 「我喜欢的歌曲」：服务端已收藏的歌曲。
  Future<List<SubsonicSong>> starredSongs() => _client.getStarredSongs();

  /// 已取回的歌词按曲目 id 复用：进出歌词态、重开播放页都不再发请求，也不
  /// 重复解析时间轴（ADR-0004 决策 5）。没有歌词的歌也缓存 null ——「没有」
  /// 同样是结果，不该每次进歌词态重查一遍。
  final Map<String, Future<SongLyrics?>> _lyricsCache = {};

  /// 一首歌的歌词；没有歌词时返回 null（界面呈现「暂无歌词」）。
  ///
  /// [artist]／[title] 只用于回退的纯文本端点，结构化歌词用不到。并发进入
  /// 同一首歌只发一次请求。
  Future<SongLyrics?> lyricsFor({
    required String songId,
    String artist = '',
    String title = '',
  }) => _lyricsCache.putIfAbsent(songId, () {
    final future = _loadLyrics(songId: songId, artist: artist, title: title);
    // 失败不留在缓存里：否则界面的「重试」拿到的是同一个失败的 Future，
    // 永远重试不动。成功的 null（没有歌词）照常缓存。
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _lyricsCache.remove(songId);
      },
    );
    return future;
  });

  Future<SongLyrics?> _loadLyrics({
    required String songId,
    required String artist,
    required String title,
  }) async {
    final raw = await _client.getLyricsForSong(
      songId: songId,
      artist: artist,
      title: title,
    );
    if (raw == null) return null;
    final lyrics = SongLyrics.fromSubsonic(raw);
    // 空行列表等同于没有歌词：界面不必区分「有结构但没内容」。
    return lyrics.lines.isEmpty ? null : lyrics;
  }

  /// 收藏／取消收藏 [target]（歌曲／专辑／歌手三选一）。
  ///
  /// `star`/`unstar` 的歌曲参数名是 `id`，专辑/歌手各自一个参数；
  /// 翻译只在这里做一次，上层不必再关心三个互斥的可空字符串。
  Future<void> setStarred(StarTarget target, {required bool starred}) {
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

  /// 某首歌的播放地址。纯拼接，不发请求。
  Uri streamUri(String songId) => _client.streamUri(songId);

  /// 某张封面的地址。纯拼接，不发请求。
  Uri coverArtUri(String coverArtId, {int? size}) =>
      _client.coverArtUri(coverArtId, size: size);
}

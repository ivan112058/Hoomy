/// Subsonic/Navidrome JSON 响应的领域模型。
/// 字段解析对缺失容错：Navidrome 版本不同返回的字段集可能有差异。
library;

class SubsonicSong {
  const SubsonicSong({
    required this.id,
    required this.title,
    this.album,
    this.artist,
    this.albumId,
    this.artistId,
    this.track,
    this.discNumber,
    this.year,
    this.durationSec,
    this.suffix,
    this.coverArtId,
    this.starred,
  });

  factory SubsonicSong.fromJson(Map<String, dynamic> json) => SubsonicSong(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        album: json['album'] as String?,
        artist: json['artist'] as String?,
        albumId: json['albumId'] as String?,
        artistId: json['artistId'] as String?,
        track: _asInt(json['track']),
        discNumber: _asInt(json['discNumber']),
        year: _asInt(json['year']),
        durationSec: _asInt(json['duration']),
        suffix: json['suffix'] as String?,
        coverArtId: json['coverArt'] as String?,
        starred: json['starred'] as String?,
      );

  final String id;
  final String title;
  final String? album;
  final String? artist;
  final String? albumId;
  final String? artistId;
  final int? track;
  final int? discNumber;
  final int? year;
  final int? durationSec;

  /// 音频格式：flac / mp3 / m4a。
  final String? suffix;
  final String? coverArtId;

  /// 非 null 表示已收藏（值为收藏时间）。
  final String? starred;

  bool get isStarred => starred != null;
}

class SubsonicAlbum {
  const SubsonicAlbum({
    required this.id,
    required this.name,
    this.artist,
    this.artistId,
    this.year,
    this.songCount,
    this.durationSec,
    this.coverArtId,
    this.starred,
    this.songs = const [],
  });

  factory SubsonicAlbum.fromJson(Map<String, dynamic> json) => SubsonicAlbum(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['title'] as String? ?? '',
        artist: json['artist'] as String?,
        artistId: json['artistId'] as String?,
        year: _asInt(json['year']),
        songCount: _asInt(json['songCount']),
        durationSec: _asInt(json['duration']),
        coverArtId: json['coverArt'] as String?,
        starred: json['starred'] as String?,
        songs: _songList(json['song']),
      );

  final String id;
  final String name;
  final String? artist;
  final String? artistId;
  final int? year;
  final int? songCount;
  final int? durationSec;
  final String? coverArtId;
  final String? starred;
  final List<SubsonicSong> songs;

  bool get isStarred => starred != null;
}

class SubsonicArtist {
  const SubsonicArtist({
    required this.id,
    required this.name,
    this.albumCount,
    this.coverArtId,
    this.starred,
    this.albums = const [],
  });

  factory SubsonicArtist.fromJson(Map<String, dynamic> json) => SubsonicArtist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        albumCount: _asInt(json['albumCount']),
        coverArtId: json['coverArt'] as String?,
        starred: json['starred'] as String?,
        albums: _albumList(json['album']),
      );

  final String id;
  final String name;
  final int? albumCount;
  final String? coverArtId;
  final String? starred;
  final List<SubsonicAlbum> albums;

  bool get isStarred => starred != null;
}

class SubsonicPlaylist {
  const SubsonicPlaylist({
    required this.id,
    required this.name,
    this.songCount,
    this.durationSec,
    this.owner,
    this.songs = const [],
  });

  factory SubsonicPlaylist.fromJson(Map<String, dynamic> json) =>
      SubsonicPlaylist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        songCount: _asInt(json['songCount']),
        durationSec: _asInt(json['duration']),
        owner: json['owner'] as String?,
        songs: _songList(json['entry']),
      );

  final String id;
  final String name;
  final int? songCount;
  final int? durationSec;
  final String? owner;

  /// 仅 getPlaylist（单歌单详情）返回，getPlaylists 列表为空。
  final List<SubsonicSong> songs;
}

class SubsonicGenre {
  const SubsonicGenre({required this.name, this.songCount, this.albumCount});

  factory SubsonicGenre.fromJson(Map<String, dynamic> json) => SubsonicGenre(
        name: json['value'] as String? ?? '',
        songCount: _asInt(json['songCount']),
        albumCount: _asInt(json['albumCount']),
      );

  final String name;
  final int? songCount;
  final int? albumCount;
}

/// 歌词：可能是纯文本（synced=false）或 LRC 行（synced=true）。
class SubsonicLyrics {
  const SubsonicLyrics({required this.synced, this.artist, this.title, this.lines = const []});

  factory SubsonicLyrics.fromJson(Map<String, dynamic> json) => SubsonicLyrics(
        synced: json['synced'] as bool? ?? false,
        // 服务端字段名为 displayArtist / displayTitle；无语言信息时 lang 为 "xxx"。
        artist: json['displayArtist'] as String?,
        title: json['displayTitle'] as String?,
        lines: (json['line'] as List<dynamic>? ?? const [])
            .map((e) => SubsonicLyricLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// 纯文本歌词时 line 里没有时间戳，整体按静态文本渲染。
  final bool synced;
  final String? artist;
  final String? title;
  final List<SubsonicLyricLine> lines;
}

class SubsonicLyricLine {
  const SubsonicLyricLine({this.startMs, this.endMs, required this.value});

  factory SubsonicLyricLine.fromJson(Map<String, dynamic> json) =>
      SubsonicLyricLine(
        startMs: _asInt(json['start']),
        endMs: _asInt(json['end']),
        value: json['value'] as String? ?? '',
      );

  final int? startMs;
  final int? endMs;
  final String value;
}

int? _asInt(Object? v) => switch (v) {
      null => null,
      int i => i,
      String s => int.tryParse(s),
      _ => null,
    };

List<SubsonicSong> _songList(Object? v) => switch (v) {
      null => const [],
      List l => l
          .whereType<Map>()
          .map((e) => SubsonicSong.fromJson(e.cast<String, dynamic>()))
          .toList(),
      Map m => [SubsonicSong.fromJson(m.cast<String, dynamic>())],
      _ => const [],
    };

List<SubsonicAlbum> _albumList(Object? v) => switch (v) {
      null => const [],
      List l => l
          .whereType<Map>()
          .map((e) => SubsonicAlbum.fromJson(e.cast<String, dynamic>()))
          .toList(),
      Map m => [SubsonicAlbum.fromJson(m.cast<String, dynamic>())],
      _ => const [],
    };

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

/// 歌词：可能是纯文本（synced=false）、逐行 LRC（synced=true）或逐字（[cueLines] 非空）。
class SubsonicLyrics {
  const SubsonicLyrics({
    required this.synced,
    this.artist,
    this.title,
    this.lines = const [],
    this.cueLines = const [],
  });

  factory SubsonicLyrics.fromJson(Map<String, dynamic> json) => SubsonicLyrics(
        synced: json['synced'] as bool? ?? false,
        // 服务端字段名为 displayArtist / displayTitle；无语言信息时 lang 为 "xxx"。
        artist: json['displayArtist'] as String?,
        title: json['displayTitle'] as String?,
        lines: _mapList(json['line'], SubsonicLyricLine.fromJson),
        // songLyrics v2：逐字时间轴（需请求 enhanced=true）。
        cueLines: _mapList(json['cueLine'], SubsonicCueLine.fromJson),
      );

  /// 纯文本歌词时 line 里没有时间戳，整体按静态文本渲染。
  final bool synced;
  final String? artist;
  final String? title;
  final List<SubsonicLyricLine> lines;

  /// 逐字时间轴；为空表示没有词级数据（不代表没有歌词）。
  final List<SubsonicCueLine> cueLines;
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

/// 逐字歌词中的一行；[value] 是整行文本，词级时间轴在 [cues] 里。
class SubsonicCueLine {
  const SubsonicCueLine({
    this.index,
    this.startMs,
    this.endMs,
    this.agentId,
    this.value = '',
    this.cues = const [],
  });

  factory SubsonicCueLine.fromJson(Map<String, dynamic> json) => SubsonicCueLine(
        index: _asInt(json['index']),
        startMs: _asInt(json['start']),
        endMs: _asInt(json['end']),
        agentId: json['agentId'] as String?,
        value: json['value'] as String? ?? '',
        cues: _mapList(json['cue'], SubsonicCue.fromJson),
      );

  final int? index;
  final int? startMs;
  final int? endMs;
  final String? agentId;
  final String value;
  final List<SubsonicCue> cues;
}

/// 逐字歌词的一个「词」。
///
/// `byteStart`/`byteEnd` 是所属行文本的 0 基闭区间 **UTF-8 字节**偏移，
/// 切片必须按字节而非字符下标，否则中文歌词会错位（ADR-0004）。
class SubsonicCue {
  const SubsonicCue({
    this.startMs,
    this.endMs,
    this.byteStart,
    this.byteEnd,
    required this.value,
  });

  factory SubsonicCue.fromJson(Map<String, dynamic> json) => SubsonicCue(
        startMs: _asInt(json['start']),
        endMs: _asInt(json['end']),
        byteStart: _asInt(json['byteStart']),
        byteEnd: _asInt(json['byteEnd']),
        value: json['value'] as String? ?? '',
      );

  final int? startMs;
  final int? endMs;
  final int? byteStart;
  final int? byteEnd;
  final String value;
}

/// 容错解析「可能是单个对象、可能是数组、也可能缺失」的子节点。
List<T> _mapList<T>(Object? v, T Function(Map<String, dynamic>) fromJson) =>
    switch (v) {
      null => const [],
      List l => l
          .whereType<Map>()
          .map((e) => fromJson(e.cast<String, dynamic>()))
          .toList(),
      Map m => [fromJson(m.cast<String, dynamic>())],
      _ => const [],
    };

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

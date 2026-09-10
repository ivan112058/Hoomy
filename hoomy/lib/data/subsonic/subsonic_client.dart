import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'models.dart';

/// 登录凭据：一台 Navidrome 服务器 + 一个用户。
class SubsonicCredentials {
  const SubsonicCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  /// 容错解析用户输入：缺协议时默认 http，去掉末尾斜杠。
  factory SubsonicCredentials.fromInput({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    var url = serverUrl.trim();
    if (url.isEmpty) throw const FormatException('服务器地址为空');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (username.trim().isEmpty) throw const FormatException('用户名为空');
    return SubsonicCredentials(
      serverUrl: url,
      username: username.trim(),
      password: password,
    );
  }

  final String serverUrl;
  final String username;
  final String password;
}

/// Subsonic 协议层错误（服务端在 200 响应里返回的 error）。
class SubsonicException implements Exception {
  const SubsonicException(this.code, this.message);

  /// Subsonic 错误码，如 40 = 用户名或密码错误。
  final int code;
  final String message;

  bool get isAuthError => code == 40 || code == 41 || code == 43;

  @override
  String toString() => 'SubsonicException($code: $message)';
}

class SubsonicClient {
  SubsonicClient({
    required this.credentials,
    Dio? dio,
    this.clientName = 'hoomy',
  }) : dio = dio ?? Dio();

  static const apiVersion = '1.16.1';

  final SubsonicCredentials credentials;
  final Dio dio;
  final String clientName;

  Map<String, dynamic> _authParams() {
    final salt = _randomSalt();
    final token = md5.convert(utf8.encode(credentials.password + salt)).toString();
    return {
      'u': credentials.username,
      't': token,
      's': salt,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  String _randomSalt() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<Map<String, dynamic>> _get(
    String endpoint, {
    Map<String, dynamic>? params,
    ResponseType responseType = ResponseType.json,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await dio.get<Map<String, dynamic>>(
        '${credentials.serverUrl}/rest/$endpoint',
        queryParameters: {..._authParams(), ...?params},
        options: Options(responseType: responseType),
      );
    } on DioException catch (e) {
      throw SubsonicException(-1, _describeNetworkError(e));
    }

    final body = response.data;
    if (body == null) throw const SubsonicException(-1, '服务器返回了空响应');
    final envelope = body['subsonic-response'] as Map<String, dynamic>?;
    if (envelope == null) {
      throw const SubsonicException(-1, '响应不是 Subsonic 格式，请确认这是 Navidrome 服务器');
    }
    final status = envelope['status'] as String?;
    if (status != 'ok') {
      final error = envelope['error'] as Map<String, dynamic>?;
      throw SubsonicException(
        error?['code'] as int? ?? 0,
        error?['message'] as String? ?? '未知错误',
      );
    }
    return envelope;
  }

  String _describeNetworkError(DioException e) {
    final inner = e.error;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '连接服务器超时';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '无法连接到服务器，请检查地址与网络';
    }
    if (e.response?.statusCode == 404) return '找不到接口路径，请确认地址指向 Navidrome';
    if (e.response?.statusCode == 502 || e.response?.statusCode == 503) {
      return '服务器暂时不可用';
    }
    return '网络错误: ${inner ?? e.message}';
  }

  /// 验证凭据，失败抛 [SubsonicException]。
  Future<void> ping() => _get('ping.view');

  // ---- 浏览 ----

  /// 所有艺术家（getArtists 的 index 分组打平，按原顺序）。
  Future<List<SubsonicArtist>> getArtists() async {
    final data = await _get('getArtists.view');
    final indexes =
        (data['artists'] as Map<String, dynamic>?)?['index'] as List<dynamic>? ??
            const [];
    return indexes
        .whereType<Map>()
        .expand((group) => group['artist'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => SubsonicArtist.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<SubsonicArtist> getArtist(String id) async {
    final data = await _get('getArtist.view', params: {'id': id});
    return SubsonicArtist.fromJson(
      (data['artist'] as Map).cast<String, dynamic>(),
    );
  }

  Future<List<SubsonicAlbum>> getAlbumList2({
    String type = 'alphabeticalByName',
    int size = 50,
    int offset = 0,
    String? genre,
  }) async {
    final data = await _get('getAlbumList2.view', params: {
      'type': type,
      'size': size,
      'offset': offset,
      'genre': ?genre,
    });
    final list =
        (data['albumList2'] as Map<String, dynamic>?)?['album'] as List<dynamic>?;
    return list?.whereType<Map>().map(_albumFromJson).toList() ?? const [];
  }

  Future<SubsonicAlbum> getAlbum(String id) async {
    final data = await _get('getAlbum.view', params: {'id': id});
    return _albumFromJson((data['album'] as Map).cast<String, dynamic>());
  }

  /// 歌曲检索；空 query 在 Navidrome 上返回全库（分页），作为“歌曲”Tab 数据源。
  Future<List<SubsonicSong>> search3Songs({
    String query = '',
    int songCount = 100,
    int songOffset = 0,
  }) async {
    final data = await _get('search3.view', params: {
      'query': query,
      'artistCount': 0,
      'albumCount': 0,
      'songCount': songCount,
      'songOffset': songOffset,
    });
    final list = (data['searchResult3'] as Map<String, dynamic>?)?['song']
        as List<dynamic>?;
    return list?.whereType<Map>().map(_songFromJson).toList() ?? const [];
  }

  // ---- 歌单 / 风格 / 收藏 ----

  Future<List<SubsonicPlaylist>> getPlaylists() async {
    final data = await _get('getPlaylists.view');
    final list = (data['playlists'] as Map<String, dynamic>?)?['playlist']
        as List<dynamic>?;
    return list?.whereType<Map>().map(_playlistFromJson).toList() ?? const [];
  }

  Future<SubsonicPlaylist> getPlaylist(String id) async {
    final data = await _get('getPlaylist.view', params: {'id': id});
    return _playlistFromJson((data['playlist'] as Map).cast<String, dynamic>());
  }

  Future<List<SubsonicGenre>> getGenres() async {
    final data = await _get('getGenres.view');
    final list = (data['genres'] as Map<String, dynamic>?)?['genre'] as List<dynamic>?;
    return list?.whereType<Map>().map(_genreFromJson).toList() ?? const [];
  }

  /// “我喜欢的歌曲”：已 star 的歌曲。
  Future<List<SubsonicSong>> getStarredSongs() async {
    final data = await _get('getStarred2.view');
    final list =
        (data['starred2'] as Map<String, dynamic>?)?['song'] as List<dynamic>?;
    return list?.whereType<Map>().map(_songFromJson).toList() ?? const [];
  }

  /// 收藏/取消收藏（songId / albumId / artistId 三选一）。
  Future<void> setStarred({
    String? songId,
    String? albumId,
    String? artistId,
    required bool starred,
  }) =>
      _get(starred ? 'star.view' : 'unstar.view', params: {
        'songId': ?songId,
        'albumId': ?albumId,
        'artistId': ?artistId,
      });

  // ---- 歌词 ----

  /// OpenSubsonic 结构化歌词（Navidrome >= 0.51.0 解析内嵌 LRC/EQ 与侧车文件）。
  /// 返回 null 表示该歌曲没有结构化歌词（可回退 [getLyrics]）。
  ///
  /// 响应结构为 `lyricsList.structuredLyrics[]`（可能多首，取第一首）。
  /// 逐字（`cueLine`/`cue`）需扩展 v2 与 `enhanced=true`，当前未解析。
  Future<SubsonicLyrics?> getStructuredLyrics(String songId) async {
    try {
      final data = await _get('getLyricsBySongId.view', params: {'id': songId});
      final list =
          (data['lyricsList'] as Map<String, dynamic>?)?['structuredLyrics']
              as List<dynamic>?;
      final candidates = list?.whereType<Map>().toList() ?? const <Map>[];
      if (candidates.isEmpty) return null;
      final parsed = SubsonicLyrics.fromJson(
        candidates.first.cast<String, dynamic>(),
      );
      return parsed.lines.isEmpty ? null : parsed;
    } on SubsonicException catch (e) {
      // 旧版服务端不认识该端点，回退旧接口。
      if (e.code == 0 || e.code == 10 || e.code == 70) return null;
      rethrow;
    }
  }

  /// 旧版纯文本歌词（getLyrics）。返回 null 表示没有。
  Future<SubsonicLyrics?> getLyrics({required String artist, required String title}) async {
    final data = await _get('getLyrics.view', params: {
      if (artist.isNotEmpty) 'artist': artist,
      if (title.isNotEmpty) 'title': title,
    });
    final lyrics = data['lyrics'] as Map<String, dynamic>?;
    final text = lyrics?['text'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => SubsonicLyricLine(value: l))
        .toList();
    return SubsonicLyrics(synced: false, artist: artist, title: title, lines: lines);
  }

  // ---- 媒体 URL（给播放器与封面组件直接使用）----

  Uri coverArtUri(String coverArtId, {int? size}) => _mediaUri('getCoverArt.view', {
        'id': coverArtId,
        'size': ?size,
      });

  /// 播放原始流：`format=raw` 关闭服务端转码（ADR-0001）。
  Uri streamUri(String songId) =>
      _mediaUri('stream.view', {'id': songId, 'format': 'raw'});

  Uri _mediaUri(String endpoint, Map<String, dynamic> params) {
    final query = {..._authParams(), ...params};
    return Uri.parse('${credentials.serverUrl}/rest/$endpoint')
        .replace(queryParameters: query.map((k, v) => MapEntry(k, v.toString())));
  }
}

SubsonicSong _songFromJson(Map m) => SubsonicSong.fromJson(m.cast<String, dynamic>());
SubsonicAlbum _albumFromJson(Map m) => SubsonicAlbum.fromJson(m.cast<String, dynamic>());
SubsonicPlaylist _playlistFromJson(Map m) =>
    SubsonicPlaylist.fromJson(m.cast<String, dynamic>());
SubsonicGenre _genreFromJson(Map m) => SubsonicGenre.fromJson(m.cast<String, dynamic>());

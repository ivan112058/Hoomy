import '../lyrics/song_lyrics.dart';
import '../subsonic/subsonic_client.dart';

/// 歌词取数：结构化优先、无结果回退纯文本（ADR-0004），并缓存解析后的结构。
///
/// 缓存按 `songId` 落在**解析之后**的领域结构上：进出歌词态、重开播放页都不再
/// 发请求，也不重复解析时间轴（ADR-0004 决策 5）。没有歌词的歌也缓存 null ——
/// 「没有」同样是结果，不该每次进歌词态重查一遍。
class LyricsRepository {
  LyricsRepository(this._client);

  final SubsonicClient _client;

  /// 进行中与已完成的取数按曲目 id 复用：并发进入同一首歌只发一次请求。
  final Map<String, Future<SongLyrics?>> _cache = {};

  /// 取一首歌的歌词；没有歌词时返回 null（界面呈现「暂无歌词」）。
  ///
  /// [artist]／[title] 只用于回退的纯文本端点，结构化歌词用不到。
  Future<SongLyrics?> lyricsFor({
    required String songId,
    String artist = '',
    String title = '',
  }) => _cache.putIfAbsent(songId, () {
    final future = _load(songId: songId, artist: artist, title: title);
    // 失败不留在缓存里：否则界面的「重试」拿到的是同一个失败的 Future，
    // 永远重试不动。成功的 null（没有歌词）照常缓存。
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _cache.remove(songId);
      },
    );
    return future;
  });

  Future<SongLyrics?> _load({
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
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../lyrics/song_lyrics.dart';
import 'album_repository.dart';
import 'artist_repository.dart';
import 'genre_repository.dart';
import 'lyrics_repository.dart';
import 'playlist_repository.dart';
import 'star_repository.dart';

/// repository 的接线处：全部由当前登录用户的协议客户端派生，未登录时为 null。
///
/// 页面只依赖这些 provider，不再直接持有协议客户端。仓库类本身不依赖
/// Riverpod，测试可注入假传输构造真实仓库。
///
/// **正在收缩**：歌曲页已改从会话取数（票据 02），其余页面随票据 03 迁移；
/// 到那时这一层连同 `subsonicClientProvider` 一并消失。

final albumRepositoryProvider = Provider<AlbumRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : AlbumRepository(client);
});

final artistRepositoryProvider = Provider<ArtistRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : ArtistRepository(client);
});

final playlistRepositoryProvider = Provider<PlaylistRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : PlaylistRepository(client);
});

final genreRepositoryProvider = Provider<GenreRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : GenreRepository(client);
});

final starRepositoryProvider = Provider<StarRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : StarRepository(client);
});

final lyricsRepositoryProvider = Provider<LyricsRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : LyricsRepository(client);
});

/// 一首歌的歌词请求身份。
///
/// 用记录（record）而不是 `SubsonicSong` 做 family 键：记录按值相等，
/// 队列重建产生的新曲目对象不会让同一个 id 重新取一次歌词。
typedef LyricsRequest = ({String songId, String artist, String title});

/// 当前曲目的歌词；界面在播放页一打开就订阅它，从而**预取**（ADR-0007），
/// 切到歌词态不再发起请求。
///
/// `autoDispose`：播放页关闭即释放本次订阅，缓存留在 [LyricsRepository] 里。
final lyricsProvider = FutureProvider.autoDispose
    .family<SongLyrics?, LyricsRequest>((ref, request) async {
      final repository = ref.watch(lyricsRepositoryProvider);
      if (repository == null) return null;
      return repository.lyricsFor(
        songId: request.songId,
        artist: request.artist,
        title: request.title,
      );
    });

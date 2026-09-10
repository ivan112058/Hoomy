import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'album_repository.dart';
import 'artist_repository.dart';
import 'genre_repository.dart';
import 'playlist_repository.dart';
import 'song_repository.dart';
import 'star_repository.dart';

/// repository 的接线处：全部由当前登录用户的协议客户端派生，未登录时为 null。
///
/// 页面只依赖这些 provider，不再直接持有协议客户端。仓库类本身不依赖
/// Riverpod，测试可注入假传输构造真实仓库。

final songRepositoryProvider = Provider<SongRepository?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  return client == null ? null : SongRepository(client);
});

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

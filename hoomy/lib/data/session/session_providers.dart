import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/song_lyrics.dart';
import '../subsonic/models.dart';
import 'session.dart';

/// 当前会话：取数的唯一入口（ADR-0015 决策 1）。
///
/// **只由登录闸口注入**：闸口挂主界面时用嵌套作用域 override 出一个本地实例，
/// 因此主界面之内会话在类型上不可能为空，页面与播放层都不必再判空，也不存在
/// 「没有数据源」这种形态。
///
/// 默认实现直接抛错：在闸口之外读到它，就说明不变量被破坏了 —— 外壳的统一
/// 兜底据此给出可读原因与重试入口，而不是一片空白。抛 [StateError]（而不是
/// `Exception`）是刻意的：Riverpod 不会自动重试一个 `Error`。
final sessionProvider = Provider<Session>((ref) {
  throw StateError('会话未注入：主界面只能挂在登录闸口之下');
});

/// 取数失败**不自动重试**。
///
/// Riverpod 默认会按退避策略重试十次；那会让「失败」这一态一闪而过，用户既
/// 看不到原因也没有可点的重试入口，而且与改动前的行为不符。失败就停在失败态，
/// 重试由用户触发（[AsyncValueView] 的「重试」）。
Duration? noAutoRetry(int retryCount, Object error) => null;

// 取数以**异步值**形态出现在接口上：页面只订阅它，取数身份、缓存与将来的失效
// 都落在会话内部（ADR-0015 决策 4）。每一条都声明 `dependencies: [sessionProvider]`，
// 这不是可选项：会话是在**嵌套作用域**里注入的（登录闸口），Riverpod 只有在依赖
// 被静态声明时才知道该把这条取数放进哪个作用域；不声明就会挂在根作用域上，读到
// 一个不存在的会话。

/// 曲库里的全部歌曲。
final allSongsProvider = FutureProvider<List<SubsonicSong>>(
  (ref) => ref.watch(sessionProvider).allSongs(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 曲库里的全部专辑。
final allAlbumsProvider = FutureProvider<List<SubsonicAlbum>>(
  (ref) => ref.watch(sessionProvider).allAlbums(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 一张专辑的详情（含曲目）。
final albumProvider = FutureProvider.family<SubsonicAlbum, String>(
  (ref, id) => ref.watch(sessionProvider).album(id),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 曲库里的全部歌手。
final allArtistsProvider = FutureProvider<List<SubsonicArtist>>(
  (ref) => ref.watch(sessionProvider).allArtists(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 一位歌手的详情（其专辑与全部歌曲）。
final artistDetailProvider = FutureProvider.family<ArtistDetail, String>(
  (ref, id) => ref.watch(sessionProvider).artistDetail(id),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 服务端的播放列表。
final playlistsProvider = FutureProvider<List<SubsonicPlaylist>>(
  (ref) => ref.watch(sessionProvider).playlists(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 一个播放列表的详情（含曲目）。
final playlistProvider = FutureProvider.family<SubsonicPlaylist, String>(
  (ref, id) => ref.watch(sessionProvider).playlist(id),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 曲库里的风格列表（空名风格已丢弃）。
final genresProvider = FutureProvider<List<SubsonicGenre>>(
  (ref) => ref.watch(sessionProvider).genres(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 某个风格下的全部歌曲。
final genreSongsProvider = FutureProvider.family<List<SubsonicSong>, String>(
  (ref, genre) => ref.watch(sessionProvider).genreSongs(genre),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 「我喜欢的歌曲」：服务端已收藏的歌曲。
final starredSongsProvider = FutureProvider<List<SubsonicSong>>(
  (ref) => ref.watch(sessionProvider).starredSongs(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

/// 一首歌的歌词请求身份。
///
/// 用记录（record）而不是 `SubsonicSong` 做 family 键：记录按值相等，
/// 队列重建产生的新曲目对象不会让同一个 id 重新取一次歌词。
typedef LyricsRequest = ({String songId, String artist, String title});

/// 当前曲目的歌词；界面在播放页一打开就订阅它，从而**预取**（ADR-0007），
/// 切到歌词态不再发起请求。
///
/// `autoDispose`：播放页关闭即释放本次订阅，缓存留在 [Session] 里。
final lyricsProvider = FutureProvider.autoDispose
    .family<SongLyrics?, LyricsRequest>(
      (ref, request) => ref.watch(sessionProvider).lyricsFor(
        songId: request.songId,
        artist: request.artist,
        title: request.title,
      ),
      dependencies: [sessionProvider],
      retry: noAutoRetry,
    );

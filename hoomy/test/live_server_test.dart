import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/repositories/album_repository.dart';
import 'package:hoomy/data/repositories/artist_repository.dart';
import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';

/// 集成测试：对真实 Navidrome 只读端点验证 repository 取数。默认不参与 `flutter test`，
/// 因为依赖局域网服务器。运行方式：
///
/// ```
/// flutter test test/live_server_test.dart \
///   --dart-define=HOOMY_TEST_SERVER=http://192.168.1.9:4533 \
///   --dart-define=HOOMY_TEST_USER=<user> \
///   --dart-define=HOOMY_TEST_PASS=<pass>
/// ```
///
/// 只调用只读端点：ping / search3 / getArtists / getArtist / getAlbum /
/// getAlbumList2 / getLyricsBySongId / getLyrics。
/// 绝不在本文件中调用 star / unstar / scrobble 等写端点。
void main() {
  const server = String.fromEnvironment('HOOMY_TEST_SERVER');
  const user = String.fromEnvironment('HOOMY_TEST_USER');
  const pass = String.fromEnvironment('HOOMY_TEST_PASS');
  final configured = server.isNotEmpty && user.isNotEmpty;

  group('真实服务器集成（只读）', () {
    late SubsonicClient client;

    setUp(() {
      client = SubsonicClient(
        credentials: SubsonicCredentials(
          serverUrl: server,
          username: user,
          password: pass,
        ),
      );
    });

    test('ping 通过', () async {
      await client.ping();
    }, skip: configured ? false : '需要 --dart-define 提供服务器地址与凭据');

    test('分页取回全库歌曲，条数与去重后一致，且确实翻过页', () async {
      final songs = await SongRepository(client).getAllSongs();

      expect(songs, isNotEmpty, reason: '曲库为空');
      expect(
        songs.map((s) => s.id).toSet().length,
        songs.length,
        reason: '分页出现重复歌曲',
      );
      // 实测 908 首，跨 2 页；断言至少需要一次翻页，覆盖 offset 路径。
      expect(songs.length, greaterThan(SongRepository.pageSize));
    }, skip: configured ? false : '未配置服务器');

    test('专辑列表非空，专辑详情带曲目列表', () async {
      final albums = await AlbumRepository(client).getAllAlbums();
      expect(albums, isNotEmpty, reason: '专辑列表为空');

      final detail = await AlbumRepository(client).getAlbum(albums.first.id);
      expect(detail.songs, isNotEmpty, reason: '专辑详情没有曲目');
    }, skip: configured ? false : '未配置服务器');

    test('歌手列表非空；歌手详情带专辑，全部歌曲无重复', () async {
      final artists = await ArtistRepository(client).getArtists();
      expect(artists, isNotEmpty, reason: '歌手列表为空');

      final withAlbums = artists.firstWhere(
        (a) => (a.albumCount ?? 0) > 0,
        orElse: () => artists.first,
      );
      final detail = await ArtistRepository(client).getArtist(withAlbums.id);
      expect(detail.albums, isNotEmpty, reason: '歌手详情没有专辑');

      final songs = await ArtistRepository(client).getArtistSongs(withAlbums.id);
      expect(songs, isNotEmpty, reason: '歌手没有取到任何歌曲');
      expect(
        songs.map((s) => s.id).toSet().length,
        songs.length,
        reason: '歌手歌曲出现重复',
      );
    }, skip: configured ? false : '未配置服务器');

    test('结构化歌词按 lyricsList.structuredLyrics 解析出时间轴', () async {
      final songs = await client.search3Songs(songCount: 12);
      expect(songs, isNotEmpty);

      SubsonicLyrics? found;
      for (final song in songs) {
        final lyrics = await client.getStructuredLyrics(song.id);
        if (lyrics != null && lyrics.lines.any((l) => l.startMs != null)) {
          found = lyrics;
          break;
        }
      }

      expect(found, isNotNull, reason: '前 12 首中未解析出带时间轴的歌词，解析路径可能仍然错误');
      expect(found!.synced, isTrue);
      // start 字段解析为毫秒，且应为非降序（第一行通常是 0）。
      expect(found.lines.first.startMs, isNotNull);
      expect(found.lines.first.value, isNotEmpty);
    }, skip: configured ? false : '未配置服务器');
  });
}

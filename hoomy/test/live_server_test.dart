import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';

/// 集成测试：对真实 Navidrome 只读端点验证客户端解析。默认不参与 `flutter test`，
/// 因为依赖局域网服务器。运行方式：
///
/// ```
/// flutter test test/live_server_test.dart \
///   --dart-define=HOOMY_TEST_SERVER=http://192.168.1.9:4533 \
///   --dart-define=HOOMY_TEST_USER=hugh \
///   --dart-define=HOOMY_TEST_PASS=hugh
/// ```
///
/// 只调用只读端点：ping / search3 / getLyricsBySongId / getLyrics。
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

    test('search3 空 query 分页取回全库，且无重复 id', () async {
      const pageSize = 500;
      final all = <String>[];
      for (var offset = 0;; offset += pageSize) {
        final page = await client.search3Songs(
          songCount: pageSize,
          songOffset: offset,
        );
        if (page.isEmpty) break;
        all.addAll(page.map((s) => s.id));
        if (page.length < pageSize) break;
      }

      expect(all, isNotEmpty, reason: '曲库为空');
      expect(all.toSet().length, all.length, reason: '分页出现重复歌曲');
      // 实测 908 首，分布在 2 页；断言至少需要一次翻页，覆盖 offset 路径。
      expect(all.length, greaterThan(pageSize));
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

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';

import 'fake_transport.dart';

/// 全库歌曲取回：`search3` 空 query、页大小 500、短页或空页终止（ADR-0005）。
void main() {
  /// 造 [count] 首可辨认的歌曲，序号从 [from] 开始。
  List<Map<String, Object?>> songPage(int from, int count) => [
        for (var i = from; i < from + count; i++)
          {'id': 's$i', 'title': '歌曲 $i'},
      ];

  /// 按 `songOffset` 返回对应页的假传输；未登记的 offset 视为空页。
  FakeTransport pagedTransport(Map<int, List<Map<String, Object?>>> pages) {
    final transport = FakeTransport();
    transport.responder = (options) {
      final offset =
          int.tryParse(options.uri.queryParameters['songOffset'] ?? '0') ?? 0;
      return jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'searchResult3': {'song': pages[offset] ?? const <Object?>[]},
        },
      });
    };
    return transport;
  }

  List<String> offsetsOf(FakeTransport transport) => transport.requests
      .map((r) => r.uri.queryParameters['songOffset'] ?? '')
      .toList();

  test('单页不足 500 首时只请求一次，返回全部', () async {
    final transport = pagedTransport({0: songPage(0, 3)});

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs.map((s) => s.id), ['s0', 's1', 's2']);
    expect(offsetsOf(transport), ['0']);
  });

  test('翻页直到短页：500 + 200 首用两次请求取回', () async {
    final transport = pagedTransport({
      0: songPage(0, 500),
      500: songPage(500, 200),
    });

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs, hasLength(700));
    expect(songs.first.id, 's0');
    expect(songs.last.id, 's699');
    expect(offsetsOf(transport), ['0', '500']);
  });

  test('恰好整页后接空页时终止', () async {
    final transport = pagedTransport({0: songPage(0, 500), 500: const []});

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs, hasLength(500));
    expect(offsetsOf(transport), ['0', '500']);
  });

  test('空库返回空列表', () async {
    final transport = pagedTransport({0: const []});

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs, isEmpty);
    expect(offsetsOf(transport), ['0']);
  });

  test('服务端返回重叠页时按 id 去重，全库条数与去重后一致', () async {
    // 第二页本应是 s500..s999，服务端却从 s400 开始，与第一页重叠 100 首。
    final transport = pagedTransport({
      0: songPage(0, 500),
      500: [...songPage(400, 100), ...songPage(500, 300)],
    });

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs, hasLength(800));
    expect(songs.map((s) => s.id).toSet(), hasLength(songs.length));
  });

  test('服务端忽略 songOffset 时不会死循环，结果去重', () async {
    final transport = FakeTransport();
    transport.responder = (_) => jsonResponse({
          'subsonic-response': {
            'status': 'ok',
            'searchResult3': {'song': songPage(0, 500)},
          },
        });

    final songs = await SongRepository(fakeClient(transport)).getAllSongs();

    expect(songs, hasLength(500));
    // 第二页整页都是重复项，立即终止；不会无限翻页。
    expect(offsetsOf(transport), ['0', '500']);
  });

  test('请求参数：空 query、页大小 500、artistCount 与 albumCount 为 0', () async {
    final transport = pagedTransport({0: songPage(0, 1)});

    await SongRepository(fakeClient(transport)).getAllSongs();

    final query = transport.lastQuery;
    expect(query['query'], '');
    expect(query['songCount'], '500');
    expect(query['songOffset'], '0');
    expect(query['artistCount'], '0');
    expect(query['albumCount'], '0');
  });

  test('翻页中途失败时抛出可读异常，不返回半截结果', () async {
    final transport = FakeTransport();
    transport.responder = (options) {
      if (options.uri.queryParameters['songOffset'] == '500') {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        );
      }
      return jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'searchResult3': {'song': songPage(0, 500)},
        },
      });
    };

    await expectLater(
      SongRepository(fakeClient(transport)).getAllSongs(),
      throwsA(
        isA<SubsonicException>()
            .having((e) => e.message, 'message', '无法连接到服务器，请检查地址与网络'),
      ),
    );
  });
}

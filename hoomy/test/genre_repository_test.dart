import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/repositories/genre_repository.dart';

import 'fake_transport.dart';

/// 风格取数：`getSongsByGenre` 按 `count`/`offset` 翻页直到短页或空页
/// （与全库歌曲同一套分页循环，ADR-0005）；空名风格在仓库边界被丢弃。
void main() {
  /// 造 [count] 首可辨认的歌曲，序号从 [from] 开始。
  List<Map<String, Object?>> songPage(int from, int count) => [
    for (var i = from; i < from + count; i++)
      {'id': 's$i', 'title': '歌曲 $i'},
  ];

  /// 按 `offset` 返回对应页的假传输；未登记的 offset 视为空页。
  FakeTransport pagedTransport(Map<int, List<Map<String, Object?>>> pages) {
    final transport = FakeTransport();
    transport.responder = (options) {
      final offset = int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
      return jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'songsByGenre': {'song': pages[offset] ?? const <Object?>[]},
        },
      });
    };
    return transport;
  }

  test('风格名与页大小随请求下发，短页即终止', () async {
    final transport = pagedTransport({0: songPage(0, 3)});

    final songs = await GenreRepository(fakeClient(transport)).getSongs('Rock');

    expect(songs.map((s) => s.id), ['s0', 's1', 's2']);
    expect(transport.requests, hasLength(1));
    expect(transport.lastQuery['genre'], 'Rock');
    expect(transport.lastQuery['count'], '500');
    expect(transport.lastQuery['offset'], '0');
  });

  test('整页后继续翻页，第二次带 offset=500', () async {
    final transport = pagedTransport({
      0: songPage(0, 500),
      500: songPage(500, 20),
    });

    final songs = await GenreRepository(fakeClient(transport)).getSongs('Rock');

    expect(songs, hasLength(520));
    expect(songs.last.id, 's519');
    expect(
      transport.requests.map((r) => r.uri.queryParameters['offset']),
      ['0', '500'],
    );
  });

  test('风格下没有歌曲时返回空列表', () async {
    final transport = pagedTransport({0: const []});

    expect(await GenreRepository(fakeClient(transport)).getSongs('Rock'), isEmpty);
  });

  test('服务端没给 value 的空名风格被丢弃，不产生点了必错的空风格', () async {
    final transport = FakeTransport()
      ..ok('getGenres.view', {
        'genres': {
          'genre': [
            {'value': 'Rock', 'songCount': 3},
            {'songCount': 1},
          ],
        },
      });

    final genres = await GenreRepository(fakeClient(transport)).getGenres();

    expect(genres.map((g) => g.name), ['Rock']);
  });
}

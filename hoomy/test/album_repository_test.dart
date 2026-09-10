import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/repositories/album_repository.dart';

import 'fake_transport.dart';

/// 专辑取数：`getAlbumList2` 分页取全量，专辑详情含曲目列表。
void main() {
  List<Map<String, Object?>> albumPage(int from, int count) => [
        for (var i = from; i < from + count; i++)
          {'id': 'al$i', 'name': '专辑 $i', 'artist': '歌手'},
      ];

  FakeTransport pagedTransport(Map<int, List<Map<String, Object?>>> pages) {
    final transport = FakeTransport();
    transport.responder = (options) {
      final offset =
          int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
      return jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'albumList2': {'album': pages[offset] ?? const <Object?>[]},
        },
      });
    };
    return transport;
  }

  test('分页取回全部专辑，按 offset 递增直到短页', () async {
    final transport = pagedTransport({
      0: albumPage(0, 500),
      500: albumPage(500, 18),
    });

    final albums = await AlbumRepository(fakeClient(transport)).getAllAlbums();

    expect(albums, hasLength(518));
    expect(albums.first.id, 'al0');
    expect(albums.last.id, 'al517');
    expect(
      transport.requests.map((r) => r.uri.queryParameters['offset']),
      ['0', '500'],
    );
  });

  test('请求按名字排序、页大小 500 且带 offset', () async {
    final transport = pagedTransport({0: albumPage(0, 1)});

    await AlbumRepository(fakeClient(transport)).getAllAlbums();

    final query = transport.lastQuery;
    expect(query['type'], 'alphabeticalByName');
    expect(query['size'], '500');
    expect(query['offset'], '0');
  });

  test('服务端返回重叠页时按 id 去重', () async {
    final transport = pagedTransport({
      0: albumPage(0, 500),
      500: [...albumPage(480, 20), ...albumPage(500, 10)],
    });

    final albums = await AlbumRepository(fakeClient(transport)).getAllAlbums();

    expect(albums, hasLength(510));
    expect(albums.map((a) => a.id).toSet(), hasLength(albums.length));
  });

  test('专辑详情取到曲目列表', () async {
    final transport = FakeTransport()
      ..ok('getAlbum.view', {
        'album': {
          'id': 'al1',
          'name': '叶惠美',
          'artist': '周杰伦',
          'year': 2003,
          'songCount': 2,
          'coverArt': 'al1',
          'song': [
            {'id': 's1', 'title': '晴天', 'track': 3, 'duration': 269},
            {'id': 's2', 'title': '以父之名', 'track': 2, 'duration': 341},
          ],
        },
      });

    final album = await AlbumRepository(fakeClient(transport)).getAlbum('al1');

    expect(album.name, '叶惠美');
    expect(album.artist, '周杰伦');
    expect(album.year, 2003);
    expect(album.songs.map((s) => s.title), ['晴天', '以父之名']);
    expect(transport.lastQuery['id'], 'al1');
  });
}

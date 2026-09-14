import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/repositories/artist_repository.dart';

import 'fake_transport.dart';

/// 歌手取数：聚合歌手列表，以及一次取回的歌手详情（专辑 + 全部歌曲）。
void main() {
  /// `ar1` 名下两张专辑，`al2` 里有一首与 `al1` 重复（用于验证去重）。
  FakeTransport artistWithAlbums() {
    final transport = FakeTransport();
    transport.responder = (options) {
      final id = options.uri.queryParameters['id'];
      final envelope = switch (id) {
        'ar1' => {
            'artist': {
              'id': 'ar1',
              'name': 'Adele',
              'album': [
                {'id': 'al1', 'name': '25'},
                {'id': 'al2', 'name': '21'},
              ],
            },
          },
        'al1' => {
            'album': {
              'id': 'al1',
              'name': '25',
              'song': [
                {'id': 's1', 'title': 'Hello'},
                {'id': 's2', 'title': 'Send My Love'},
              ],
            },
          },
        'al2' => {
            'album': {
              'id': 'al2',
              'name': '21',
              // s2 与 al1 重复，用于验证去重。
              'song': [
                {'id': 's2', 'title': 'Send My Love'},
                {'id': 's3', 'title': 'Rolling in the Deep'},
              ],
            },
          },
        _ => throw StateError('未注册的 id: $id'),
      };
      return jsonResponse({
        'subsonic-response': {'status': 'ok', ...envelope},
      });
    };
    return transport;
  }

  test('歌手列表来自 getArtists 的 index 分组打平', () async {
    final transport = FakeTransport()
      ..ok('getArtists.view', {
        'artists': {
          'index': [
            {
              'name': 'A',
              'artist': [
                {'id': 'ar1', 'name': 'Adele', 'albumCount': 3},
              ],
            },
            {
              'name': '#',
              'artist': [
                {'id': 'ar2', 'name': '五月天', 'albumCount': 9},
              ],
            },
          ],
        },
      });

    final artists = await ArtistRepository(fakeClient(transport)).getArtists();

    expect(artists.map((a) => a.name), ['Adele', '五月天']);
    expect(artists.map((a) => a.albumCount), [3, 9]);
  });

  test('歌手详情取到该歌手的专辑', () async {
    final transport = FakeTransport()
      ..ok('getArtist.view', {
        'artist': {
          'id': 'ar1',
          'name': 'Adele',
          'albumCount': 2,
          'album': [
            {'id': 'al1', 'name': '25', 'songCount': 11},
            {'id': 'al2', 'name': '21', 'songCount': 11},
          ],
        },
      })
      ..ok('getAlbum.view', {
        'album': {'id': 'al1', 'name': '25'},
      });

    final detail =
        await ArtistRepository(fakeClient(transport)).getArtistDetail('ar1');

    expect(detail.artist.name, 'Adele');
    expect(detail.artist.albums.map((a) => a.name), ['25', '21']);
  });

  test('歌手全部歌曲：逐张专辑取曲目后打平，按 id 去重', () async {
    final transport = artistWithAlbums();

    final detail =
        await ArtistRepository(fakeClient(transport)).getArtistDetail('ar1');

    expect(detail.songs.map((s) => s.id), ['s1', 's2', 's3']);
    expect(detail.songs.map((s) => s.title), [
      'Hello',
      'Send My Love',
      'Rolling in the Deep',
    ]);
  });

  test('歌手详情只发一次 getArtist', () async {
    final transport = artistWithAlbums();

    await ArtistRepository(fakeClient(transport)).getArtistDetail('ar1');

    expect(
      transport.requests
          .where((r) => r.uri.pathSegments.last == 'getArtist.view')
          .length,
      1,
      reason: '页面为一个歌手只该发一次 getArtist',
    );
  });

  test('歌手没有专辑时全部歌曲为空', () async {
    final transport = FakeTransport()
      ..ok('getArtist.view', {
        'artist': {'id': 'ar1', 'name': '无名'},
      });

    final detail =
        await ArtistRepository(fakeClient(transport)).getArtistDetail('ar1');

    expect(detail.songs, isEmpty);
  });
}

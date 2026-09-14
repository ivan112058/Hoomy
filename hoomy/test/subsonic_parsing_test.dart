import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/subsonic_client.dart';

import 'fake_transport.dart';

/// S1 接缝：各端点的固定响应 → 领域模型解析，含字段缺失的容错。
///
/// 写端点（`star`/`unstar`，票据 12）只在这里验证**请求组装**：固定响应来自
/// 假传输，绝不触达真实服务器。
void main() {
  group('ping', () {
    test('成功时正常返回', () async {
      final transport = FakeTransport()..ok('ping.view');

      await fakeClient(transport).ping();

      expect(transport.lastEndpoint, 'ping.view');
    });
  });

  group('search3', () {
    test('解析歌曲的歌手、专辑、时长、格式、封面与收藏标记', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {
                'id': 's1',
                'title': '晴天',
                'artist': '周杰伦',
                'album': '叶惠美',
                'albumId': 'al1',
                'artistId': 'ar1',
                'track': 3,
                'discNumber': 1,
                'year': 2003,
                'duration': 269,
                'suffix': 'flac',
                'coverArt': 'al1',
                'starred': '2026-09-01T00:00:00Z',
              },
              {
                'id': 's2',
                'title': '以父之名',
                'duration': 341,
                'suffix': 'mp3',
              },
            ],
          },
        });

      final songs = await fakeClient(transport).search3Songs(songCount: 500);

      expect(songs, hasLength(2));
      final first = songs.first;
      expect(first.id, 's1');
      expect(first.title, '晴天');
      expect(first.artist, '周杰伦');
      expect(first.album, '叶惠美');
      expect(first.albumId, 'al1');
      expect(first.artistId, 'ar1');
      expect(first.track, 3);
      expect(first.discNumber, 1);
      expect(first.year, 2003);
      expect(first.durationSec, 269);
      expect(first.suffix, 'flac');
      expect(first.coverArtId, 'al1');
      expect(first.isStarred, isTrue);
      expect(songs[1].isStarred, isFalse);
    });

    test('缺 coverArt／duration／artist 时不崩，对应字段为空', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '无元数据'},
            ],
          },
        });

      final song = (await fakeClient(transport).search3Songs()).single;

      expect(song.title, '无元数据');
      expect(song.coverArtId, isNull);
      expect(song.durationSec, isNull);
      expect(song.artist, isNull);
      expect(song.album, isNull);
      expect(song.artistId, isNull);
    });

    test('数值字段以字符串返回时也能解析', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': 'x', 'duration': '180', 'track': '7'},
            ],
          },
        });

      final song = (await fakeClient(transport).search3Songs()).single;

      expect(song.durationSec, 180);
      expect(song.track, 7);
    });

    test('列表里混入非对象元素时跳过，而不是崩溃', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              '这不是歌曲',
              42,
              {'id': 's1', 'title': '晴天'},
            ],
          },
        });

      final songs = await fakeClient(transport).search3Songs();

      expect(songs.map((s) => s.id), ['s1']);
    });
  });

  group('getArtists / getArtist', () {
    test('getArtists 打平 index 分组，保留顺序', () async {
      final transport = FakeTransport()
        ..ok('getArtists.view', {
          'artists': {
            'ignoredArticles': 'The El La',
            'index': [
              {
                'name': 'A',
                'artist': [
                  {
                    'id': 'ar1',
                    'name': 'Adele',
                    'albumCount': 3,
                    'coverArt': 'ar1',
                    'starred': '2026-09-01T00:00:00Z',
                  },
                ],
              },
              {
                'name': '#',
                'artist': [
                  {'id': 'ar2', 'name': '五月天'},
                ],
              },
            ],
          },
        });

      final artists = await fakeClient(transport).getArtists();

      expect(artists.map((a) => a.name), ['Adele', '五月天']);
      expect(artists.first.albumCount, 3);
      expect(artists.first.coverArtId, 'ar1');
      expect(artists.first.isStarred, isTrue);
      expect(artists[1].isStarred, isFalse);
    });

    test('getArtist 解析歌手的专辑列表', () async {
      final transport = FakeTransport()
        ..ok('getArtist.view', {
          'artist': {
            'id': 'ar1',
            'name': 'Adele',
            'albumCount': 2,
            'album': [
              {
                'id': 'al1',
                'name': '25',
                'songCount': 11,
                'duration': 3000,
                'year': 2015,
                'coverArt': 'al1',
              },
            ],
          },
        });

      final artist = await fakeClient(transport).getArtist('ar1');

      expect(artist.id, 'ar1');
      expect(artist.albums.single.name, '25');
      expect(artist.albums.single.songCount, 11);
      expect(artist.albums.single.year, 2015);
      expect(transport.lastQuery['id'], 'ar1');
    });

    test('歌手缺 coverArt／专辑列表时字段为空', () async {
      final transport = FakeTransport()
        ..ok('getArtist.view', {
          'artist': {'id': 'ar1', 'name': '无名'},
        });

      final artist = await fakeClient(transport).getArtist('ar1');

      expect(artist.coverArtId, isNull);
      expect(artist.albums, isEmpty);
    });
  });

  group('getAlbumList2 / getAlbum', () {
    test('getAlbumList2 解析专辑列表并传递分页与风格参数', () async {
      final transport = FakeTransport()
        ..ok('getAlbumList2.view', {
          'albumList2': {
            'album': [
              {
                'id': 'al1',
                'name': 'Kind of Blue',
                'artist': 'Miles Davis',
                'artistId': 'ar9',
                'songCount': 5,
                'duration': 2700,
                'coverArt': 'al1',
                'year': 1959,
              },
            ],
          },
        });

      final albums = await fakeClient(transport).getAlbumList2(
        type: 'byGenre',
        size: 20,
        offset: 40,
        genre: 'Jazz',
      );

      expect(albums.single.name, 'Kind of Blue');
      expect(albums.single.artistId, 'ar9');
      expect(albums.single.year, 1959);
      expect(transport.lastQuery['type'], 'byGenre');
      expect(transport.lastQuery['size'], '20');
      expect(transport.lastQuery['offset'], '40');
      expect(transport.lastQuery['genre'], 'Jazz');
    });

    test('未指定风格时不带 genre 参数', () async {
      final transport = FakeTransport()..ok('getAlbumList2.view');

      await fakeClient(transport).getAlbumList2();

      expect(transport.lastQuery.containsKey('genre'), isFalse);
      expect(transport.lastQuery['type'], 'alphabeticalByName');
    });

    test('getAlbum 解析专辑内曲目', () async {
      final transport = FakeTransport()
        ..ok('getAlbum.view', {
          'album': {
            'id': 'al1',
            'name': '叶惠美',
            'artist': '周杰伦',
            'artistId': 'ar1',
            'year': 2003,
            'songCount': 11,
            'duration': 2600,
            'coverArt': 'al1',
            'song': [
              {'id': 's1', 'title': '晴天', 'duration': 269},
              {'id': 's2', 'title': '以父之名', 'duration': 341},
            ],
          },
        });

      final album = await fakeClient(transport).getAlbum('al1');

      expect(album.name, '叶惠美');
      expect(album.coverArtId, 'al1');
      expect(album.songs.map((s) => s.title), ['晴天', '以父之名']);
      expect(transport.lastQuery['id'], 'al1');
    });

    test('专辑缺 coverArt 时字段为空且曲目列表为空', () async {
      final transport = FakeTransport()
        ..ok('getAlbum.view', {
          'album': {'id': 'al1', 'name': '无封面专辑'},
        });

      final album = await fakeClient(transport).getAlbum('al1');

      expect(album.coverArtId, isNull);
      expect(album.songs, isEmpty);
    });
  });

  group('getPlaylists / getPlaylist', () {
    test('getPlaylists 解析歌单列表（不含曲目）', () async {
      final transport = FakeTransport()
        ..ok('getPlaylists.view', {
          'playlists': {
            'playlist': [
              {
                'id': 'p1',
                'name': '通勤',
                'songCount': 12,
                'duration': 2400,
                'owner': 'alice',
              },
            ],
          },
        });

      final playlists = await fakeClient(transport).getPlaylists();

      expect(playlists.single.id, 'p1');
      expect(playlists.single.name, '通勤');
      expect(playlists.single.songCount, 12);
      expect(playlists.single.owner, 'alice');
      expect(playlists.single.songs, isEmpty);
    });

    test('getPlaylist 解析歌单曲目（entry 节点）', () async {
      final transport = FakeTransport()
        ..ok('getPlaylist.view', {
          'playlist': {
            'id': 'p1',
            'name': '通勤',
            'songCount': 2,
            'entry': [
              {'id': 's1', 'title': '晴天', 'artist': '周杰伦'},
              {'id': 's2', 'title': '以父之名'},
            ],
          },
        });

      final playlist = await fakeClient(transport).getPlaylist('p1');

      expect(playlist.name, '通勤');
      expect(playlist.songs.map((s) => s.id), ['s1', 's2']);
      expect(playlist.songs.first.artist, '周杰伦');
      expect(transport.lastQuery['id'], 'p1');
    });
  });

  group('getGenres / getStarred2', () {
    test('getGenres 从 value 字段解析风格名', () async {
      final transport = FakeTransport()
        ..ok('getGenres.view', {
          'genres': {
            'genre': [
              {'value': 'Rock', 'songCount': 100, 'albumCount': 10},
              {'value': 'Jazz', 'songCount': 5, 'albumCount': 2},
            ],
          },
        });

      final genres = await fakeClient(transport).getGenres();

      expect(genres.map((g) => g.name), ['Rock', 'Jazz']);
      expect(genres.first.songCount, 100);
      expect(genres.first.albumCount, 10);
    });

    test('getStarred2 解析已收藏歌曲', () async {
      final transport = FakeTransport()
        ..ok('getStarred2.view', {
          'starred2': {
            'song': [
              {
                'id': 's1',
                'title': '晴天',
                'starred': '2026-09-01T00:00:00Z',
              },
            ],
          },
        });

      final songs = await fakeClient(transport).getStarredSongs();

      expect(songs.single.id, 's1');
      expect(songs.single.isStarred, isTrue);
    });

    test('未收藏任何歌曲时返回空列表', () async {
      final transport = FakeTransport()
        ..ok('getStarred2.view', {
          'starred2': {'song': <Object>[]},
        });

      expect(await fakeClient(transport).getStarredSongs(), isEmpty);
    });
  });

  group('star / unstar 写参数', () {
    test('歌曲的 id 参数名是 id，不是 songId，且走 star.view', () async {
      final transport = FakeTransport()..ok('star.view');

      await fakeClient(transport).setStarred(songId: 's1', starred: true);

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['id'], 's1');
      expect(
        transport.lastQuery.containsKey('songId'),
        isFalse,
        reason: 'Subsonic 规范的歌曲参数名是 id；写成 songId 会被服务端忽略',
      );
      expect(transport.lastQuery.containsKey('albumId'), isFalse);
      expect(transport.lastQuery.containsKey('artistId'), isFalse);
    });

    test('专辑用 albumId、歌手用 artistId，且不带 id', () async {
      final albumTransport = FakeTransport()..ok('star.view');
      await fakeClient(
        albumTransport,
      ).setStarred(albumId: 'al1', starred: true);
      expect(albumTransport.lastQuery['albumId'], 'al1');
      expect(albumTransport.lastQuery.containsKey('id'), isFalse);

      final artistTransport = FakeTransport()..ok('star.view');
      await fakeClient(
        artistTransport,
      ).setStarred(artistId: 'ar1', starred: true);
      expect(artistTransport.lastQuery['artistId'], 'ar1');
      expect(artistTransport.lastQuery.containsKey('id'), isFalse);
    });

    test('取消收藏走 unstar.view', () async {
      final transport = FakeTransport()..ok('unstar.view');

      await fakeClient(transport).setStarred(songId: 's1', starred: false);

      expect(transport.lastEndpoint, 'unstar.view');
      expect(transport.lastQuery['id'], 's1');
    });

    test('服务端错误映射为可读异常', () async {
      final transport = FakeTransport()..fail('star.view', 70, '数据未找到');

      await expectLater(
        fakeClient(transport).setStarred(songId: 'gone', starred: true),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.code, 'code', 70)
              .having((e) => e.message, 'message', '数据未找到'),
        ),
      );
    });
  });

  group('容器节点缺失', () {
    test('响应里没有数据节点时返回空列表而不是崩溃', () async {
      final transport = FakeTransport()
        ..ok('search3.view')
        ..ok('getArtists.view')
        ..ok('getAlbumList2.view')
        ..ok('getPlaylists.view')
        ..ok('getGenres.view')
        ..ok('getStarred2.view');
      final client = fakeClient(transport);

      expect(await client.search3Songs(), isEmpty);
      expect(await client.getArtists(), isEmpty);
      expect(await client.getAlbumList2(), isEmpty);
      expect(await client.getPlaylists(), isEmpty);
      expect(await client.getGenres(), isEmpty);
      expect(await client.getStarredSongs(), isEmpty);
    });
  });

  group('credentials', () {
    test('省略协议时补 http，并去掉末尾斜杠', () {
      final credentials = SubsonicCredentials.fromInput(
        serverUrl: 'nas.local:4533/',
        username: ' alice ',
        password: 'p',
      );

      expect(credentials.serverUrl, 'http://nas.local:4533');
      expect(credentials.username, 'alice');
    });
  });
}

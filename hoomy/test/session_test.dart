import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/lyrics/song_lyrics.dart';
import 'package:hoomy/data/session/paged_fetch.dart';
import 'package:hoomy/data/session/session.dart';
import 'package:hoomy/data/star/star_target.dart';
import 'package:hoomy/data/subsonic/subsonic_client.dart';

import 'fake_transport.dart';

/// 票据 01：会话是取数的唯一入口（ADR-0015）。
///
/// 全部跨**假传输**验证 —— 会话内部的分页、解析与地址拼接都是真的，只有
/// HTTP 被替换掉。断言的是会话对外给出的结果，不是它内部调了哪个方法。
void main() {
  Session sessionWith(FakeTransport transport) => Session(
        credentials: testCredentials,
        transport: Dio()..httpClientAdapter = transport,
      );

  /// 造 [count] 首可辨认的歌曲，序号从 [from] 开始。
  List<Map<String, Object?>> songPage(int from, int count) => [
        for (var i = from; i < from + count; i++)
          {'id': 's$i', 'title': '歌曲 $i'},
      ];

  group('全库取回', () {
    test('按 offset 翻页直到短页，重叠页被去重', () async {
      final transport = FakeTransport();
      transport.responder = (options) {
        final offset =
            int.tryParse(options.uri.queryParameters['songOffset'] ?? '0') ?? 0;
        final page = switch (offset) {
          0 => songPage(0, 500),
          // 第二页开头重复上一页的最后两首，且不足一页：翻页到此为止。
          500 => [
              {'id': 's498', 'title': '重复'},
              {'id': 's499', 'title': '重复'},
              ...songPage(500, 200),
            ],
          _ => <Map<String, Object?>>[],
        };
        return jsonResponse({
          'subsonic-response': {
            'status': 'ok',
            'searchResult3': {'song': page},
          },
        });
      };

      final songs = await sessionWith(transport).allSongs();

      expect(songs, hasLength(700), reason: '两页共 702 条，去重后 700');
      expect(songs.first.id, 's0');
      expect(songs.last.id, 's699');
      expect(
        transport.requests
            .map((r) => r.uri.queryParameters['songOffset'])
            .toList(),
        ['0', '500'],
      );
    });

    test('曲库为空时返回空列表', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {'song': <Object?>[]},
        });

      expect(await sessionWith(transport).allSongs(), isEmpty);
    });

    test('请求带全库分页参数：页大小就是会话内部那一个常量', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {'song': <Object?>[]},
        });

      await sessionWith(transport).allSongs();

      final query = transport.lastQuery;
      expect(query['songCount'], '$kListPageSize');
      expect(query['songOffset'], '0');
      expect(query['query'], '', reason: '空 query 即全库');
    });

    test('字段缺失的响应不抛异常，缺的字段留空', () async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1'},
            ],
          },
        });

      final songs = await sessionWith(transport).allSongs();

      expect(songs.single.id, 's1');
      expect(songs.single.durationSec, isNull);
    });

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

    List<String?> offsetsOf(FakeTransport transport) => transport.requests
        .map((r) => r.uri.queryParameters['songOffset'])
        .toList();

    test('单页不足一页时只请求一次', () async {
      final transport = pagedTransport({0: songPage(0, 3)});

      final songs = await sessionWith(transport).allSongs();

      expect(songs.map((s) => s.id), ['s0', 's1', 's2']);
      expect(offsetsOf(transport), ['0']);
    });

    test('恰好整页后接空页时终止', () async {
      final transport = pagedTransport({0: songPage(0, 500), 500: const []});

      final songs = await sessionWith(transport).allSongs();

      expect(songs, hasLength(500));
      expect(offsetsOf(transport), ['0', '500']);
    });

    test('服务端忽略 offset 时不会死循环，结果去重', () async {
      final transport = FakeTransport();
      transport.responder = (_) => jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'searchResult3': {'song': songPage(0, 500)},
        },
      });

      final songs = await sessionWith(transport).allSongs();

      expect(songs, hasLength(500));
      // 第二页整页都是重复项，立即终止；不会无限翻页。
      expect(offsetsOf(transport), ['0', '500']);
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
        sessionWith(transport).allSongs(),
        throwsA(
          isA<SubsonicException>().having(
            (e) => e.message,
            'message',
            '无法连接到服务器，请检查地址与网络',
          ),
        ),
      );
    });
  });

  group('地址', () {
    test('播放地址带认证查询串与 format=raw（不转码）', () {
      final uri = sessionWith(FakeTransport()).streamUri('s1');

      expect(uri.path, endsWith('/rest/stream.view'));
      expect(uri.queryParameters['id'], 's1');
      expect(uri.queryParameters['format'], 'raw');
      expect(uri.queryParameters['u'], testCredentials.username);
      expect(uri.queryParameters['t'], isNotEmpty);
      expect(uri.queryParameters['s'], hasLength(12));
    });

    test('封面地址带 id 与尺寸；不传尺寸时不编一个', () {
      final session = sessionWith(FakeTransport());

      expect(session.coverArtUri('c1').queryParameters['id'], 'c1');
      expect(session.coverArtUri('c1').queryParameters.containsKey('size'), isFalse);
      expect(session.coverArtUri('c1', size: 300).queryParameters['size'], '300');
    });
  });

  group('收藏写', () {
    FakeTransport accepting() {
      final transport = FakeTransport();
      transport.responder =
          (options) => jsonResponse({'subsonic-response': {'status': 'ok'}});
      return transport;
    }

    test('歌曲／专辑／歌手三种粒度翻成各自互斥的参数', () async {
      final transport = accepting();
      final session = sessionWith(transport);

      await session.setStarred(songStar('s1'), starred: true);
      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['id'], 's1');
      expect(transport.lastQuery.containsKey('albumId'), isFalse);

      await session.setStarred(albumStar('a1'), starred: false);
      expect(transport.lastEndpoint, 'unstar.view');
      expect(transport.lastQuery['albumId'], 'a1');
      expect(transport.lastQuery.containsKey('id'), isFalse);

      await session.setStarred(artistStar('ar1'), starred: true);
      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['artistId'], 'ar1');
    });

    test('「我喜欢的歌曲」取自服务端已收藏列表', () async {
      final transport = FakeTransport()
        ..ok('getStarred2.view', {
          'starred2': {
            'song': [
              {'id': 's1', 'title': '喜欢的歌'},
            ],
          },
        });

      final songs = await sessionWith(transport).starredSongs();

      expect(songs.single.title, '喜欢的歌');
    });
  });

  group('歌词', () {
    test('有行级时间轴时判定为逐行档', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'line': [
                  {'start': 0, 'value': '第一行'},
                  {'start': 1500, 'value': '第二行'},
                ],
              },
            ],
          },
        });

      final lyrics = await sessionWith(transport).lyricsFor(songId: 's1');

      expect(lyrics, isNotNull);
      expect(lyrics!.tier, LyricTier.line);
      expect(lyrics.lines.map((l) => l.text), ['第一行', '第二行']);
    });

    test('没有歌词时返回 null，由界面呈现「暂无歌词」', () async {
      // 结构化无结果时按 ADR-0004 回退纯文本端点，两边都没有才是真的没有。
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view');

      expect(await sessionWith(transport).lyricsFor(songId: 's1'), isNull);
    });

    test('同一首歌只取一次：解析结果按曲目缓存', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': false,
                'line': [
                  {'value': '纯文本'},
                ],
              },
            ],
          },
        });
      final session = sessionWith(transport);

      final first = await session.lyricsFor(songId: 's1');
      final second = await session.lyricsFor(songId: 's1');

      expect(identical(first, second), isTrue);
      expect(transport.requests, hasLength(1));
    });

    test('「没有歌词」也缓存下来，不重复查', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view');
      final session = sessionWith(transport);

      expect(await session.lyricsFor(songId: 's1'), isNull);
      expect(await session.lyricsFor(songId: 's1'), isNull);

      // 结构化 + 纯文本各一次，第二次调用走缓存。
      expect(transport.requests, hasLength(2));
    });

    test('结构化无结果时回退纯文本，带上歌手与标题', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view', {
          'lyrics': {'value': '第一行\n第二行'},
        });

      final lyrics = await sessionWith(transport)
          .lyricsFor(songId: 's1', artist: '周杰伦', title: '晴天');

      expect(lyrics!.tier, LyricTier.plain);
      expect(lyrics.lines.map((l) => l.text), ['第一行', '第二行']);
      expect(transport.lastEndpoint, 'getLyrics.view');
      expect(transport.lastQuery['artist'], '周杰伦');
      expect(transport.lastQuery['title'], '晴天');
    });

    test('不同曲目各自缓存、各自取数', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': false,
                'line': [
                  {'value': '歌词'},
                ],
              },
            ],
          },
        });
      final session = sessionWith(transport);

      await session.lyricsFor(songId: 's1');
      await session.lyricsFor(songId: 's2');

      expect(transport.requests, hasLength(2));
      expect(transport.requests.first.uri.queryParameters['id'], 's1');
      expect(transport.lastQuery['id'], 's2');
    });

    test('失败的取数不缓存，重试会重新请求', () async {
      final transport = FakeTransport()
        ..fail('getLyricsBySongId.view', 40, 'Wrong username or password');
      final session = sessionWith(transport);

      await expectLater(session.lyricsFor(songId: 's1'), throwsA(anything));
      expect(transport.requests, hasLength(1));

      // 服务端恢复后重试：不能被上一次的失败缓存挡住。
      transport.ok('getLyricsBySongId.view', {
        'lyricsList': {
          'structuredLyrics': [
            {
              'synced': false,
              'line': [
                {'value': '重试成功'},
              ],
            },
          ],
        },
      });
      final lyrics = await session.lyricsFor(songId: 's1');

      expect(lyrics!.lines.single.text, '重试成功');
      expect(transport.requests, hasLength(2));
    });
  });

  group('专辑、歌手、播放列表、风格都经会话取回', () {
    test('全部专辑与专辑详情（含曲目）', () async {
      final transport = FakeTransport()
        ..ok('getAlbumList2.view', {
          'albumList2': {
            'album': [
              {'id': 'al1', 'name': '叶惠美'},
            ],
          },
        })
        ..ok('getAlbum.view', {
          'album': {
            'id': 'al1',
            'name': '叶惠美',
            'song': [
              {'id': 's1', 'title': '晴天'},
            ],
          },
        });
      final session = sessionWith(transport);

      final albums = await session.allAlbums();
      final detail = await session.album('al1');

      expect(albums.single.name, '叶惠美');
      expect(detail.songs.single.title, '晴天');
    });

    test('全部歌手由 index 分组打平；歌手详情含专辑与其全部歌曲', () async {
      final transport = FakeTransport();
      transport.responder = (options) {
        final endpoint = options.uri.pathSegments.last;
        final id = options.uri.queryParameters['id'];
        final body = switch ((endpoint, id)) {
          ('getArtists.view', _) => {
              'artists': {
                'index': [
                  {
                    'artist': [
                      {'id': 'ar1', 'name': 'Adele', 'albumCount': 1},
                    ],
                  },
                ],
              },
            },
          ('getArtist.view', 'ar1') => {
              'artist': {
                'id': 'ar1',
                'name': 'Adele',
                'album': [
                  {'id': 'al1', 'name': '25'},
                ],
              },
            },
          ('getAlbum.view', 'al1') => {
              'album': {
                'id': 'al1',
                'name': '25',
                'song': [
                  {'id': 's1', 'title': 'Hello'},
                ],
              },
            },
          _ => throw StateError('未注册：$endpoint id=$id'),
        };
        return jsonResponse({
          'subsonic-response': {'status': 'ok', ...body},
        });
      };
      final session = sessionWith(transport);

      final artists = await session.allArtists();
      final detail = await session.artistDetail('ar1');

      expect(artists.single.name, 'Adele');
      expect(detail.artist.albums.single.name, '25');
      expect(detail.songs.single.title, 'Hello');
    });

    test('播放列表列表与播放列表详情（含曲目）', () async {
      final transport = FakeTransport()
        ..ok('getPlaylists.view', {
          'playlists': {
            'playlist': [
              {'id': 'p1', 'name': '通勤', 'songCount': 1},
            ],
          },
        })
        ..ok('getPlaylist.view', {
          'playlist': {
            'id': 'p1',
            'name': '通勤',
            'entry': [
              {'id': 's1', 'title': '晴天'},
            ],
          },
        });
      final session = sessionWith(transport);

      final playlists = await session.playlists();
      final detail = await session.playlist('p1');

      expect(playlists.single.name, '通勤');
      expect(detail.songs.single.title, '晴天');
    });

    test('风格列表丢掉空名，风格曲目按风格取回', () async {
      final transport = FakeTransport()
        ..ok('getGenres.view', {
          'genres': {
            'genre': [
              {'value': 'Rock', 'songCount': 1},
              {'songCount': 9},
            ],
          },
        })
        ..ok('getSongsByGenre.view', {
          'songsByGenre': {
            'song': [
              {'id': 's1', 'title': '摇滚'},
            ],
          },
        });
      final session = sessionWith(transport);

      final genres = await session.genres();
      final songs = await session.genreSongs('Rock');

      expect(genres.single.name, 'Rock', reason: '空名风格点进去只会换来服务端错误');
      expect(songs.single.title, '摇滚');
      expect(transport.lastQuery['genre'], 'Rock');
    });

    test('专辑按 offset 翻页取全量，请求带排序与页大小', () async {
      final transport = FakeTransport();
      transport.responder = (options) {
        final offset =
            int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
        final page = switch (offset) {
          0 => [
              for (var i = 0; i < 500; i++)
                {'id': 'al$i', 'name': '专辑 $i'},
            ],
          500 => [
              for (var i = 500; i < 518; i++)
                {'id': 'al$i', 'name': '专辑 $i'},
            ],
          _ => <Map<String, Object?>>[],
        };
        return jsonResponse({
          'subsonic-response': {
            'status': 'ok',
            'albumList2': {'album': page},
          },
        });
      };

      final albums = await sessionWith(transport).allAlbums();

      expect(albums, hasLength(518));
      expect(albums.last.id, 'al517');
      expect(
        transport.requests.map((r) => r.uri.queryParameters['offset']),
        ['0', '500'],
      );
      final query = transport.requests.first.uri.queryParameters;
      expect(query['type'], 'alphabeticalByName');
      expect(query['size'], '$kListPageSize');
    });

    test('风格曲目按 offset 翻页，第二次带 offset=500', () async {
      final transport = FakeTransport();
      transport.responder = (options) {
        final offset =
            int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
        final page = switch (offset) {
          0 => songPage(0, 500),
          500 => songPage(500, 20),
          _ => <Map<String, Object?>>[],
        };
        return jsonResponse({
          'subsonic-response': {
            'status': 'ok',
            'songsByGenre': {'song': page},
          },
        });
      };
      final session = sessionWith(transport);

      final songs = await session.genreSongs('Rock');

      expect(songs, hasLength(520));
      expect(songs.last.id, 's519');
      expect(
        transport.requests.map((r) => r.uri.queryParameters['offset']),
        ['0', '500'],
      );
      expect(transport.requests.first.uri.queryParameters['genre'], 'Rock');
      expect(transport.requests.first.uri.queryParameters['count'], '$kListPageSize');
    });

    test('歌手详情逐张专辑取曲目后打平、按 id 去重，且只发一次 getArtist', () async {
      // `ar1` 名下两张专辑，`al2` 里有一首与 `al1` 重复（用于验证去重）。
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

      final detail = await sessionWith(transport).artistDetail('ar1');

      expect(detail.songs.map((s) => s.id), ['s1', 's2', 's3']);
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

      final detail = await sessionWith(transport).artistDetail('ar1');

      expect(detail.songs, isEmpty);
    });
  });
}

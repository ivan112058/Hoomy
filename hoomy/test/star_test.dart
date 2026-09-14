import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/album_repository.dart';
import 'package:hoomy/data/repositories/artist_repository.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/star_repository.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/more/starred_songs_page.dart';
import 'package:hoomy/features/player/playback_page.dart';
import 'package:hoomy/features/shared/song_tile.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 12 的行为验收：收藏写路径的乐观更新、失败回滚与同目标互斥，以及
/// 歌曲行／播放页／专辑／歌手四个入口与「我喜欢的歌曲」。
///
/// 写请求全部打在 [FakeTransport] 上（S1 接缝），不对任何真实服务器调用
/// `star`/`unstar`。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  SubsonicSong song({
    String id = 's1',
    String title = '晴天',
    bool starred = false,
  }) => SubsonicSong(
    id: id,
    title: title,
    artist: '周杰伦',
    album: '叶惠美',
    durationSec: 269,
    starred: starred ? '2026-09-01T00:00:00Z' : null,
  );

  /// 页面测试台：收藏仓库指向假传输，未登录态下不触达真实客户端。
  Widget harness(
    Widget child, {
    required FakeTransport transport,
    PlaybackController? controller,
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [
      subsonicClientProvider.overrideWithValue(null),
      starRepositoryProvider.overrideWithValue(
        StarRepository(fakeClient(transport)),
      ),
      ...overrides,
      if (controller != null)
        playerControllerProvider.overrideWithValue(controller),
    ],
    child: MaterialApp(theme: hoomyLightTheme(), home: child),
  );

  /// 已发出的写请求次数。
  int starWriteCount(FakeTransport transport) => transport.requests
      .where(
        (r) =>
            r.uri.pathSegments.last == 'star.view' ||
            r.uri.pathSegments.last == 'unstar.view',
      )
      .length;

  group('歌曲行', () {
    testWidgets('乐观更新：点击后立刻点亮，不等网络往返', (tester) async {
      final transport = FakeTransport()..ok('star.view');
      final gate = Completer<void>();
      transport.gate = gate.future;

      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(song: song())),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.star_border));
      // 请求已走到传输层但被 gate 挡住：响应尚未返回。
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsOneWidget, reason: '乐观更新：不等网络往返');
      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['id'], 's1');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('写失败：回滚界面状态并给出可读提示', (tester) async {
      final transport = FakeTransport()..fail('star.view', 70, '数据未找到');

      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(song: song())),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_border), findsOneWidget, reason: '失败回滚');
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text('收藏失败：数据未找到'), findsOneWidget);
    });

    testWidgets('取消收藏失败：回滚到已收藏并提示「取消收藏失败」', (tester) async {
      final transport = FakeTransport()..fail('unstar.view', 70, '数据未找到');

      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(song: song(starred: true))),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);

      await tester.tap(find.byIcon(Icons.star));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsOneWidget, reason: '失败回滚到已收藏');
      expect(find.text('取消收藏失败：数据未找到'), findsOneWidget);
    });

    testWidgets('同一目标重复点击只发一次请求（互斥）', (tester) async {
      final transport = FakeTransport()..ok('star.view');
      final gate = Completer<void>();
      transport.gate = gate.future;

      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(song: song())),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();
      expect(starWriteCount(transport), 1);

      // 第一次仍在途：第二次点击被忽略，不产生交错的重复请求。
      await tester.tap(find.byIcon(Icons.star));
      await tester.pumpAndSettle();
      expect(starWriteCount(transport), 1, reason: '同目标互斥');

      gate.complete();
      await tester.pumpAndSettle();
      expect(starWriteCount(transport), 1);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('新的一行不残留本地乐观值，初值取服务端状态', (tester) async {
      final transport = FakeTransport()..ok('star.view');

      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(key: const ValueKey('a'), song: song())),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);

      // 服务端仍说未收藏：新的一行回到未收藏，不继承上一行的乐观值。
      await tester.pumpWidget(
        harness(
          Scaffold(body: SongTile(key: const ValueKey('b'), song: song())),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);

      // 服务端已改为收藏：新的一行直接是实心星（初值来自服务端）。
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: SongTile(
              key: const ValueKey('c'),
              song: song(starred: true),
            ),
          ),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('播放页', () {
    testWidgets('顶栏可收藏当前曲目', (tester) async {
      final engine = FakePlayerEngine();
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
      );
      addTearDown(controller.dispose);
      final transport = FakeTransport()..ok('star.view');

      await tester.pumpWidget(
        harness(
          PlaybackPage(controller: controller),
          transport: transport,
          controller: controller,
        ),
      );
      await controller.playQueue([song()]);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['id'], 's1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('没有当前曲目时不出现收藏按钮', (tester) async {
      final engine = FakePlayerEngine();
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        harness(
          PlaybackPage(controller: controller),
          transport: FakeTransport(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无播放内容'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });
  });

  group('专辑与歌手', () {
    testWidgets('专辑网格单元可收藏，写请求带 albumId', (tester) async {
      final transport = FakeTransport()
        ..ok('star.view')
        ..ok('getAlbumList2.view', {
          'albumList2': {
            'album': [
              {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦'},
            ],
          },
        });

      await tester.pumpWidget(
        harness(
          const AlbumsPage(),
          transport: transport,
          overrides: [
            albumRepositoryProvider.overrideWithValue(
              AlbumRepository(fakeClient(transport)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['albumId'], 'al1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('歌手列表行可收藏，写请求带 artistId', (tester) async {
      final transport = FakeTransport()
        ..ok('star.view')
        ..ok('getArtists.view', {
          'artists': {
            'index': [
              {
                'name': 'A',
                'artist': [
                  {'id': 'ar1', 'name': 'Adele', 'albumCount': 3},
                ],
              },
            ],
          },
        });

      await tester.pumpWidget(
        harness(
          const ArtistsPage(),
          transport: transport,
          overrides: [
            artistRepositoryProvider.overrideWithValue(
              ArtistRepository(fakeClient(transport)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['artistId'], 'ar1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('专辑已收藏时星标点亮（初值来自服务端）', (tester) async {
      final transport = FakeTransport()
        ..ok('getAlbumList2.view', {
          'albumList2': {
            'album': [
              {
                'id': 'al1',
                'name': '叶惠美',
                'artist': '周杰伦',
                'starred': '2026-09-01T00:00:00Z',
              },
            ],
          },
        });

      await tester.pumpWidget(
        harness(
          const AlbumsPage(),
          transport: transport,
          overrides: [
            albumRepositoryProvider.overrideWithValue(
              AlbumRepository(fakeClient(transport)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('歌手已收藏时星标点亮（初值来自服务端）', (tester) async {
      final transport = FakeTransport()
        ..ok('getArtists.view', {
          'artists': {
            'index': [
              {
                'name': 'A',
                'artist': [
                  {
                    'id': 'ar1',
                    'name': 'Adele',
                    'albumCount': 3,
                    'starred': '2026-09-01T00:00:00Z',
                  },
                ],
              },
            ],
          },
        });

      await tester.pumpWidget(
        harness(
          const ArtistsPage(),
          transport: transport,
          overrides: [
            artistRepositoryProvider.overrideWithValue(
              ArtistRepository(fakeClient(transport)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });
  });

  group('我喜欢的歌曲', () {
    testWidgets('列出服务端已收藏歌曲，并可从本列表播放', (tester) async {
      final transport = FakeTransport()
        ..ok('getStarred2.view', {
          'starred2': {
            'song': [
              {
                'id': 's1',
                'title': '晴天',
                'artist': '周杰伦',
                'album': '叶惠美',
                'starred': '2026-09-01T00:00:00Z',
              },
            ],
          },
        });
      final engine = FakePlayerEngine();
      final controller = PlaybackController(
        engine: engine,
        streamUriOf: resolveUri,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        harness(
          const StarredSongsPage(),
          transport: transport,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('晴天'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget, reason: '服务端状态是已收藏');

      await tester.tap(find.text('晴天'));
      await tester.pumpAndSettle();

      expect(engine.lastLoadedId, 's1');
    });

    testWidgets('服务端清空后重新进入显示空态', (tester) async {
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

      await tester.pumpWidget(
        harness(
          const StarredSongsPage(key: ValueKey('first')),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('晴天'), findsOneWidget);

      // 服务端已无收藏：重新进入以服务端为准。
      transport.ok('getStarred2.view', {
        'starred2': {'song': <Object>[]},
      });
      await tester.pumpWidget(
        harness(
          const StarredSongsPage(key: ValueKey('second')),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('晴天'), findsNothing);
      expect(find.text('还没有收藏的歌曲'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/genre_repository.dart';
import 'package:hoomy/data/repositories/playlist_repository.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/star_repository.dart';
import 'package:hoomy/features/more/genre_list_page.dart';
import 'package:hoomy/features/more/more_page.dart';
import 'package:hoomy/features/playlists/playlists_page.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 13 的行为验收：播放列表只读浏览与整单播放、风格列表与风格曲目。
///
/// 全部请求打在 [FakeTransport] 上（S1 接缝）；本票据不调用任何写端点，
/// 「只读」由最后一条用例显式断言。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  /// 页面测试台：三个 repository 指向**同一个**假传输，于是「页面发了哪些
  /// 请求」与「有没有写端点」可以在同一处断言。
  Widget harness(
    Widget page, {
    required FakeTransport transport,
    PlaybackController? controller,
  }) {
    final client = fakeClient(transport);
    return ProviderScope(
      overrides: [
        subsonicClientProvider.overrideWithValue(null),
        playlistRepositoryProvider.overrideWithValue(
          PlaylistRepository(client),
        ),
        genreRepositoryProvider.overrideWithValue(GenreRepository(client)),
        starRepositoryProvider.overrideWithValue(StarRepository(client)),
        if (controller != null)
          playerControllerProvider.overrideWithValue(controller),
      ],
      child: MaterialApp(theme: hoomyLightTheme(), home: page),
    );
  }

  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(engine: engine, streamUriOf: resolveUri);
    addTearDown(controller.dispose);
    return controller;
  }

  /// 两个播放列表的固定响应，与实测服务器同形。
  FakeTransport playlistsTransport() => FakeTransport()
    ..ok('getPlaylists.view', {
      'playlists': {
        'playlist': [
          {'id': 'p1', 'name': '通勤', 'songCount': 3, 'owner': 'alice'},
          {'id': 'p2', 'name': '深夜', 'songCount': 0},
        ],
      },
    });

  /// 「通勤」的曲目详情。
  void registerPlaylistDetail(FakeTransport transport) => transport.ok(
    'getPlaylist.view',
    {
      'playlist': {
        'id': 'p1',
        'name': '通勤',
        'songCount': 3,
        'entry': [
          {'id': 's1', 'title': '晴天', 'artist': '周杰伦', 'album': '叶惠美'},
          {'id': 's2', 'title': '以父之名', 'artist': '周杰伦', 'album': '叶惠美'},
          {'id': 's3', 'title': '东风破', 'artist': '周杰伦', 'album': '叶惠美'},
        ],
      },
    },
  );

  group('播放列表列表', () {
    testWidgets('显示服务端的播放列表名与曲目数', (tester) async {
      await tester.pumpWidget(
        harness(const PlaylistsPage(), transport: playlistsTransport()),
      );
      await tester.pumpAndSettle();

      expect(find.text('通勤'), findsOneWidget);
      expect(find.text('3 首'), findsOneWidget);
      expect(find.text('深夜'), findsOneWidget);
      expect(find.text('0 首'), findsOneWidget);
    });

    testWidgets('服务器上没有播放列表时显示可读文案', (tester) async {
      final transport = FakeTransport()..ok('getPlaylists.view');

      await tester.pumpWidget(
        harness(const PlaylistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();

      expect(find.text('服务器上还没有播放列表'), findsOneWidget);
    });
  });

  group('播放列表详情', () {
    testWidgets('点播放列表进入详情，按 id 取回曲目并显示', (tester) async {
      final transport = playlistsTransport();
      registerPlaylistDetail(transport);

      await tester.pumpWidget(
        harness(const PlaylistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('通勤'));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'getPlaylist.view');
      expect(transport.lastQuery['id'], 'p1');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);
      expect(find.text('东风破'), findsOneWidget);
      // 层级返回：详情页由 AppBar 自动给出返回键（Tab 根页则没有）。
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('「播放全部」以整份播放列表为队列，从第一首开始播', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = playlistsTransport();
      registerPlaylistDetail(transport);

      await tester.pumpWidget(
        harness(
          const PlaylistsPage(),
          transport: transport,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('通勤'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('播放全部'));
      await tester.pumpAndSettle();

      expect(engine.loadedIds, ['s1']);
      expect(engine.playCount, 1);
      expect(
        controller.session.queue.queue.map((s) => s.id),
        ['s1', 's2', 's3'],
        reason: '队列是整份播放列表，不是单曲',
      );
      expect(controller.session.queue.currentIndex, 0);

      // 队列可继续推进：下一首就是播放列表的第二首。
      await controller.next();
      await tester.pumpAndSettle();
      expect(engine.lastLoadedId, 's2');
    });

    testWidgets('点某一首：队列仍是整份播放列表，从这一首开始', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = playlistsTransport();
      registerPlaylistDetail(transport);

      await tester.pumpWidget(
        harness(
          const PlaylistsPage(),
          transport: transport,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('通勤'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('以父之名'));
      await tester.pumpAndSettle();

      expect(engine.lastLoadedId, 's2');
      expect(controller.session.queue.currentIndex, 1);
      expect(controller.session.queue.queue.map((s) => s.id), ['s1', 's2', 's3']);
    });

    testWidgets('空播放列表显示可读文案而不是空白', (tester) async {
      final transport = playlistsTransport()
        ..ok('getPlaylist.view', {
          'playlist': {'id': 'p2', 'name': '深夜', 'songCount': 0},
        });

      await tester.pumpWidget(
        harness(const PlaylistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('深夜'));
      await tester.pumpAndSettle();

      expect(find.text('这个播放列表还没有曲目'), findsOneWidget);
      expect(find.text('播放全部'), findsNothing, reason: '空播放列表没有可播的东西');
    });

    testWidgets('曲目可收藏：走票据 12 的星标与 star 端点', (tester) async {
      final transport = playlistsTransport()..ok('star.view');
      registerPlaylistDetail(transport);

      await tester.pumpWidget(
        harness(const PlaylistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('通勤'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_border), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['id'], 's1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('风格', () {
    FakeTransport genresTransport() => FakeTransport()
      ..ok('getGenres.view', {
        'genres': {
          'genre': [
            {'value': 'Rock', 'songCount': 100, 'albumCount': 10},
            {'value': 'Jazz', 'songCount': 5, 'albumCount': 2},
          ],
        },
      });

    testWidgets('列表显示曲库里的风格及其曲目数', (tester) async {
      await tester.pumpWidget(
        harness(const GenreListPage(), transport: genresTransport()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('100 首'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('5 首'), findsOneWidget);
    });

    testWidgets('曲库里没有风格信息时显示可读文案', (tester) async {
      final transport = FakeTransport()..ok('getGenres.view');

      await tester.pumpWidget(
        harness(const GenreListPage(), transport: transport),
      );
      await tester.pumpAndSettle();

      expect(find.text('曲库里还没有风格信息'), findsOneWidget);
    });

    testWidgets('点风格进入该风格的曲目列表，带上风格名取数并可播放', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);
      final transport = genresTransport()
        ..ok('getSongsByGenre.view', {
          'songsByGenre': {
            'song': [
              {'id': 's1', 'title': '晴天', 'artist': '周杰伦'},
              {'id': 's2', 'title': '以父之名', 'artist': '周杰伦'},
            ],
          },
        });

      await tester.pumpWidget(
        harness(
          const GenreListPage(),
          transport: transport,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'getSongsByGenre.view');
      expect(transport.lastQuery['genre'], 'Rock');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);

      await tester.tap(find.text('以父之名'));
      await tester.pumpAndSettle();

      expect(engine.lastLoadedId, 's2');
      expect(controller.session.queue.queue.map((s) => s.id), ['s1', 's2']);
    });

    testWidgets('风格下没有曲目时显示可读文案', (tester) async {
      final transport = genresTransport()..ok('getSongsByGenre.view');

      await tester.pumpWidget(
        harness(const GenreListPage(), transport: transport),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(find.text('这个风格下还没有曲目'), findsOneWidget);
    });
  });

  group('「更多」页入口', () {
    testWidgets('播放列表与风格两个入口都能进入对应页面', (tester) async {
      final transport = playlistsTransport()
        ..ok('getGenres.view', {
          'genres': {
            'genre': [
              {'value': 'Rock', 'songCount': 100},
            ],
          },
        });

      await tester.pumpWidget(harness(const MorePage(), transport: transport));
      await tester.pumpAndSettle();

      expect(find.text('播放列表'), findsOneWidget);
      expect(find.text('风格'), findsOneWidget);

      await tester.tap(find.text('播放列表'));
      await tester.pumpAndSettle();
      expect(find.text('通勤'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('风格'));
      await tester.pumpAndSettle();
      expect(find.text('Rock'), findsOneWidget);
    });
  });

  testWidgets('播放列表与风格页面只发出只读端点', (tester) async {
    final transport = playlistsTransport()..ok('getGenres.view');
    registerPlaylistDetail(transport);

    await tester.pumpWidget(
      harness(const PlaylistsPage(), transport: transport),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('通勤'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      harness(const GenreListPage(), transport: transport),
    );
    await tester.pumpAndSettle();

    const readOnly = {
      'getPlaylists.view',
      'getPlaylist.view',
      'getGenres.view',
      'getSongsByGenre.view',
    };
    expect(transport.requests, isNotEmpty);
    for (final request in transport.requests) {
      expect(
        readOnly,
        contains(request.uri.pathSegments.last),
        reason: '本票据只读，不得调用任何写端点',
      );
    }
  });
}

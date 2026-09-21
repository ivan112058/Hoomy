import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/cover/cover_cache.dart';
import 'package:hoomy/data/cover/cover_cache_provider.dart';
import 'package:hoomy/data/session/session_providers.dart';
import 'package:hoomy/data/star/star_target.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/albums/album_detail_page.dart';
import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artist_detail_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/shared/star_button.dart';
import 'package:hoomy/player/playback_controller.dart';
import 'package:hoomy/player/player_providers.dart';

import 'fake_player_engine.dart';
import 'fake_transport.dart';

/// 票据 14 的行为验收：专辑详情与歌手详情。
///
/// 页面经**会话**取数（真会话 + 假传输，ADR-0015 测试决策），写请求只打
/// [FakeTransport]（S1 接缝）；「不请求 150dp 头部大图」用记录封面请求尺寸的
/// 假缓存断言。
void main() {
  Uri resolveUri(String id) =>
      Uri.parse('http://nas.local:4533/rest/stream.view?id=$id&format=raw');

  /// 页面测试台：会话指向假传输，于是「页面发了哪些请求」与「有没有写端点」
  /// 都能在同一处断言。
  Widget harness(
    Widget page, {
    required FakeTransport transport,
    PlaybackController? controller,
    CoverCache? coverCache,
  }) => ProviderScope(
    overrides: [
      sessionOrNullProvider.overrideWithValue(fakeSession(transport)),
      coverCacheProvider.overrideWithValue(coverCache),
      if (controller != null)
        playerControllerProvider.overrideWithValue(controller),
    ],
    child: MaterialApp(theme: hoomyLightTheme(), home: page),
  );

  PlaybackController newController(FakePlayerEngine engine) {
    final controller = PlaybackController(
      engine: engine,
      streamUriOf: resolveUri,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// 引用专辑详情里那张专辑：网格点进来的对象（封面与详情同 id 便于复用缓存）。
  const albumSummary = SubsonicAlbum(
    id: 'al1',
    name: '叶惠美',
    artist: '周杰伦',
    coverArtId: 'al1',
  );

  /// 引用歌手详情里的歌手。
  const artistSummary = SubsonicArtist(id: 'ar1', name: 'Adele', albumCount: 2);

  /// 曲库固定响应：专辑网格、专辑详情、歌手列表、歌手详情与其专辑曲目。
  ///
  /// 歌手名下的专辑用 `ar-al1`/`ar-al2`，与专辑页的 `al1` 分开，
  /// 免得两种场景返回同一份曲目、掩盖「歌手全部歌曲」的取数路径。
  FakeTransport libraryTransport() {
    final transport = FakeTransport();
    transport.responder = (options) {
      final endpoint = options.uri.pathSegments.last;
      final id = options.uri.queryParameters['id'];
      final body = switch (endpoint) {
        'getAlbumList2.view' => {
          'albumList2': {
            'album': [
              {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦', 'coverArt': 'al1'},
            ],
          },
        },
        'getAlbum.view' => switch (id) {
          'al1' => {
            'album': {
              'id': 'al1',
              'name': '叶惠美',
              'artist': '周杰伦',
              'year': 2003,
              'songCount': 2,
              'coverArt': 'al1',
              'song': [
                {
                  'id': 's1',
                  'title': '晴天',
                  'artist': '周杰伦',
                  'album': '叶惠美',
                  'track': 3,
                  'duration': 269,
                },
                {
                  'id': 's2',
                  'title': '以父之名',
                  'artist': '周杰伦',
                  'album': '叶惠美',
                  'track': 2,
                  'duration': 341,
                },
              ],
            },
          },
          'ar-al1' => {
            'album': {
              'id': 'ar-al1',
              'name': '25',
              'artist': 'Adele',
              'songCount': 1,
              'coverArt': 'ar-al1',
              'song': [
                {
                  'id': 'as1',
                  'title': 'Hello',
                  'artist': 'Adele',
                  'album': '25',
                  'track': 1,
                  'duration': 295,
                },
              ],
            },
          },
          'ar-al2' => {
            'album': {
              'id': 'ar-al2',
              'name': '21',
              'artist': 'Adele',
              'songCount': 1,
              'coverArt': 'ar-al2',
              'song': [
                {
                  'id': 'as2',
                  'title': 'Rolling in the Deep',
                  'artist': 'Adele',
                  'album': '21',
                  'track': 2,
                  'duration': 228,
                },
              ],
            },
          },
          _ => throw StateError('未注册的专辑 id：$id'),
        },
        'getArtists.view' => {
          'artists': {
            'index': [
              {
                'name': 'A',
                'artist': [
                  {'id': 'ar1', 'name': 'Adele', 'albumCount': 2},
                ],
              },
            ],
          },
        },
        'getArtist.view' => {
          'artist': {
            'id': 'ar1',
            'name': 'Adele',
            'albumCount': 2,
            'album': [
              {'id': 'ar-al1', 'name': '25', 'songCount': 1, 'coverArt': 'ar-al1'},
              {'id': 'ar-al2', 'name': '21', 'songCount': 1, 'coverArt': 'ar-al2'},
            ],
          },
        },
        'star.view' => <String, Object?>{},
        _ => throw StateError('未注册的端点：$endpoint'),
      };
      return jsonResponse({
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
      });
    };
    return transport;
  }

  /// 收藏按钮按目标找：详情页头部一个，专辑网格单元里还各有一个。
  Finder starFor(StarTarget target) => find.byWidgetPredicate(
    (widget) => widget is StarButton && widget.target == target,
  );

  group('专辑详情', () {
    testWidgets('点专辑网格进入详情：封面、专辑名、艺术家、年份、曲目数量与曲目列表', (tester) async {
      final transport = libraryTransport();

      await tester.pumpWidget(harness(const AlbumsPage(), transport: transport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('叶惠美'));
      await tester.pumpAndSettle();

      // 详情按点中的 id 取数。
      expect(transport.lastEndpoint, 'getAlbum.view');
      expect(transport.lastQuery['id'], 'al1');

      final detail = find.byType(AlbumDetailPage);
      // 专辑名在标题栏；头部不重复显示（否则同一名字出现两次）。
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('叶惠美')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.byType(CoverArt)),
        findsOneWidget,
        reason: '专辑详情显示封面',
      );
      expect(
        find.descendant(of: detail, matching: find.text('周杰伦')),
        findsOneWidget,
      );
      expect(find.text('2003 年'), findsOneWidget);
      expect(find.text('2 首'), findsOneWidget, reason: '专辑详情显示曲目数量');
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);

      // 层级返回：由 AppBar 自动给出返回键，路由是层级页面的 MaterialPageRoute
      // （全屏播放页用的是自下而上的覆盖层路由，两者动效语法不同）。
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(detail)),
        isA<MaterialPageRoute<void>>(),
      );
    });

    testWidgets('歌曲行显示音轨号', (tester) async {
      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: libraryTransport(),
        ),
      );
      await tester.pumpAndSettle();

      Finder rowOf(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(HoomyListRow));
      expect(
        find.descendant(of: rowOf('晴天'), matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf('以父之名'), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('「全部播放」以整张专辑为队列，从第一首开始顺序播放', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: libraryTransport(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('全部播放'));
      await tester.pumpAndSettle();

      expect(controller.snapshot.queue.queue.map((s) => s.id), ['s1', 's2']);
      expect(controller.snapshot.queue.currentIndex, 0);
      expect(controller.snapshot.queue.shuffle, isFalse);
      expect(engine.loadedIds, ['s1']);
      expect(engine.playCount, 1);
    });

    testWidgets('「随机播放」打开随机，从其中一首开始', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: libraryTransport(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('随机播放'));
      await tester.pumpAndSettle();

      expect(controller.snapshot.queue.shuffle, isTrue);
      expect(
        controller.snapshot.queue.queue.map((s) => s.id).toSet(),
        {'s1', 's2'},
        reason: '队列仍是整张专辑',
      );
      // 起点是随机的：只断言它落在专辑里，不断言具体是哪一首。
      expect(engine.loadedIds, hasLength(1));
      expect({'s1', 's2'}, contains(engine.loadedIds.single));
      expect(engine.playCount, 1);
    });

    testWidgets('专辑可收藏：写请求带 albumId', (tester) async {
      final transport = libraryTransport();

      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(starFor(albumStar('al1')));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['albumId'], 'al1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('专辑没有曲目时显示可读文案', (tester) async {
      final transport = libraryTransport();
      transport.responder = (options) => jsonResponse({
        'subsonic-response': {
          'status': 'ok',
          'album': {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦'},
        },
      });

      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('这个专辑还没有曲目'), findsOneWidget);
      expect(find.text('全部播放'), findsNothing, reason: '没有可播的东西');
    });

    testWidgets('不出现「加播放列表」「加队列」入口', (tester) async {
      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: libraryTransport(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('播放列表'), findsNothing);
      expect(find.textContaining('队列'), findsNothing);
      expect(find.textContaining('加入'), findsNothing);
    });

    testWidgets('不请求 150dp 头部大图：封面沿用专辑网格的缓存身份', (tester) async {
      final cache = _RecordingCoverCache();

      await tester.pumpWidget(
        harness(
          const AlbumDetailPage(album: albumSummary),
          transport: libraryTransport(),
          coverCache: cache,
        ),
      );
      await tester.pumpAndSettle();

      expect(cache.sizes, isNotEmpty, reason: '封面仍要显示');
      expect(
        cache.sizes,
        everyElement(isNot(150)),
        reason: '不做 150dp 头部大图：详情不按头部尺寸另请求一张封面',
      );
      expect(
        cache.sizes,
        [null],
        reason: '与专辑网格同一缓存身份（不带 size），命中网格已下载的那张',
      );
    });
  });

  group('歌手详情', () {
    testWidgets('点歌手列表进入详情：显示该歌手的专辑与全部歌曲', (tester) async {
      // 手机尺寸（窄屏、够高）：专辑网格与全部歌曲都落在同一屏里。
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transport = libraryTransport();

      await tester.pumpWidget(
        harness(const ArtistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adele'));
      await tester.pumpAndSettle();

      final endpoints = transport.requests
          .map((r) => r.uri.pathSegments.last)
          .toList();
      expect(endpoints, contains('getArtist.view'));
      expect(endpoints.where((e) => e == 'getAlbum.view').length, 2);
      // 只发一次 getArtist（详情一次取回专辑与全部歌曲）。
      expect(endpoints.where((e) => e == 'getArtist.view').length, 1);
      final artistRequest = transport.requests.firstWhere(
        (r) => r.uri.pathSegments.last == 'getArtist.view',
      );
      expect(artistRequest.uri.queryParameters['id'], 'ar1');

      final detail = find.byType(ArtistDetailPage);
      expect(
        find.descendant(of: detail, matching: find.text('2 张专辑')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Adele')),
        findsOneWidget,
      );
      // 专辑：走网格，可再点进专辑详情。
      expect(find.text('25'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      // 全部歌曲：跨专辑打平。
      expect(find.text('全部歌曲'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Rolling in the Deep'), findsOneWidget);

      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('25')),
        findsOneWidget,
      );
    });

    testWidgets('「全部播放」以该歌手的全部歌曲为队列，从第一首开始', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(
        harness(
          const ArtistDetailPage(artist: artistSummary),
          transport: libraryTransport(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('全部播放'));
      await tester.pumpAndSettle();

      expect(controller.snapshot.queue.queue.map((s) => s.id), ['as1', 'as2']);
      expect(controller.snapshot.queue.currentIndex, 0);
      expect(engine.loadedIds, ['as1']);
    });

    testWidgets('「随机播放」打开随机，从其中一首开始', (tester) async {
      final engine = FakePlayerEngine();
      final controller = newController(engine);

      await tester.pumpWidget(
        harness(
          const ArtistDetailPage(artist: artistSummary),
          transport: libraryTransport(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('随机播放'));
      await tester.pumpAndSettle();

      expect(controller.snapshot.queue.shuffle, isTrue);
      expect(
        controller.snapshot.queue.queue.map((s) => s.id).toSet(),
        {'as1', 'as2'},
      );
      expect(engine.loadedIds, hasLength(1));
      expect({'as1', 'as2'}, contains(engine.loadedIds.single));
    });

    testWidgets('歌手可收藏：写请求带 artistId', (tester) async {
      final transport = libraryTransport();

      await tester.pumpWidget(
        harness(
          const ArtistDetailPage(artist: artistSummary),
          transport: transport,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(starFor(artistStar('ar1')));
      await tester.pumpAndSettle();

      expect(transport.lastEndpoint, 'star.view');
      expect(transport.lastQuery['artistId'], 'ar1');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('不出现「加播放列表」「加队列」入口', (tester) async {
      await tester.pumpWidget(
        harness(
          const ArtistDetailPage(artist: artistSummary),
          transport: libraryTransport(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('播放列表'), findsNothing);
      expect(find.textContaining('队列'), findsNothing);
      expect(find.textContaining('加入'), findsNothing);
    });

    testWidgets('详情页只发出只读端点', (tester) async {
      final transport = libraryTransport();

      await tester.pumpWidget(
        harness(const AlbumsPage(), transport: transport),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('叶惠美'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        harness(const ArtistsPage(), transport: transport),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adele'));
      await tester.pumpAndSettle();

      const readOnly = {
        'getAlbumList2.view',
        'getAlbum.view',
        'getArtists.view',
        'getArtist.view',
      };
      expect(transport.requests, isNotEmpty);
      for (final request in transport.requests) {
        expect(
          readOnly,
          contains(request.uri.pathSegments.last),
          reason: '详情页只有取数，不得调用任何写端点',
        );
      }
    });
  });
}

/// 记录封面请求尺寸的假缓存：详情页「不请求 150dp 头部大图」的断言用它。
///
/// `file` 被覆盖为直接返回 null（不落盘、不下载），只留下调用时的尺寸。
class _RecordingCoverCache extends CoverCache {
  _RecordingCoverCache()
    : super(directory: Directory('/nonexistent'), fetch: (_) async {
        return Uint8List(0);
      });

  final List<int?> sizes = [];

  @override
  Future<File?> file(String coverArtId, {int? size, required Uri uri}) {
    sizes.add(size);
    return Future<File?>.value(null);
  }
}

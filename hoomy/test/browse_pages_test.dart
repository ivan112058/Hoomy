import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/album_repository.dart';
import 'package:hoomy/data/repositories/artist_repository.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/songs/songs_page.dart';

import 'fake_transport.dart';

/// 三个浏览页经 repository 取数，以及失败时的可重试错误态。
void main() {
  Widget harness(Widget page, List<Override> overrides) => ProviderScope(
        overrides: [
          // 页面不再直接持有协议客户端；封面等媒体 URL 未涉及本测试。
          subsonicClientProvider.overrideWithValue(null),
          ...overrides,
        ],
        child: MaterialApp(home: page),
      );

  group('歌曲页', () {
    testWidgets('经 SongRepository 显示歌曲，且不显示总数或页码', (tester) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '晴天', 'artist': '周杰伦', 'album': '叶惠美'},
              {'id': 's2', 'title': '以父之名', 'artist': '周杰伦', 'album': '叶惠美'},
            ],
          },
        });

      await tester.pumpWidget(harness(
        const SongsPage(),
        [songRepositoryProvider.overrideWithValue(SongRepository(fakeClient(transport)))],
      ));
      await tester.pumpAndSettle();

      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);
      // `searchResult3` 不返回总数：界面不得编造「共 N 首」或页码。
      expect(find.textContaining('共'), findsNothing);
      expect(find.textContaining('首'), findsNothing);
      expect(find.textContaining('页'), findsNothing);
    });

    testWidgets('取数失败显示可重试错误态，重试后恢复', (tester) async {
      // 同一仓库的第一次取数失败、第二次成功，验证「重试」真的重新取数。
      final transport = FakeTransport();
      var calls = 0;
      transport.responder = (options) {
        calls++;
        if (calls == 1) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection refused',
          );
        }
        return jsonResponse({
          'subsonic-response': {
            'status': 'ok',
            'searchResult3': {
              'song': [
                {'id': 's1', 'title': '晴天'},
              ],
            },
          },
        });
      };
      final repository = SongRepository(fakeClient(transport));

      await tester.pumpWidget(harness(
        const SongsPage(),
        [songRepositoryProvider.overrideWithValue(repository)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('无法连接到服务器，请检查地址与网络'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });
  });

  testWidgets('专辑页经 AlbumRepository 显示专辑', (tester) async {
    final transport = FakeTransport()
      ..ok('getAlbumList2.view', {
        'albumList2': {
          'album': [
            {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦'},
            {'id': 'al2', 'name': '范特西', 'artist': '周杰伦'},
          ],
        },
      });

    await tester.pumpWidget(harness(
      const AlbumsPage(),
      [albumRepositoryProvider.overrideWithValue(AlbumRepository(fakeClient(transport)))],
    ));
    await tester.pumpAndSettle();

    expect(find.text('叶惠美'), findsOneWidget);
    expect(find.text('范特西'), findsOneWidget);
  });

  testWidgets('歌手列表页经 ArtistRepository 显示歌手', (tester) async {
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
          ],
        },
      });

    await tester.pumpWidget(harness(
      const ArtistsPage(),
      [artistRepositoryProvider.overrideWithValue(ArtistRepository(fakeClient(transport)))],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Adele'), findsOneWidget);
    expect(find.text('3 张专辑'), findsOneWidget);
  });

  testWidgets('空曲库显示空态文案而不是空白', (tester) async {
    final transport = FakeTransport()..ok('search3.view');

    await tester.pumpWidget(harness(
      const SongsPage(),
      [songRepositoryProvider.overrideWithValue(SongRepository(fakeClient(transport)))],
    ));
    await tester.pumpAndSettle();

    expect(find.text('曲库是空的'), findsOneWidget);
  });
}

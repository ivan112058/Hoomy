import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/songs/songs_page.dart';

import 'fake_transport.dart';

/// 三个浏览页经会话显示数据，以及失败时的可重试错误态。
///
/// 用例只注入「真会话 + 假传输」（ADR-0015 测试决策）：会话及其取数逻辑是真的，
/// 只有 HTTP 被替换掉；页面不再有「没有数据源」的空白分支。
void main() {
  Widget harness(Widget page, List<Override> overrides) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: page),
      );

  group('歌曲页', () {
    testWidgets('从会话取数显示歌曲，且不显示总数或页码', (tester) async {
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
        sessionOverrides(transport),
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
      // 同一条假传输第一次失败、第二次成功，验证「重试」真的重新取数。
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

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
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

    testWidgets('取数在途时显示载入态', (tester) async {
      final transport = FakeTransport()..ok('search3.view');
      final gate = Completer<void>();
      transport.gate = gate.future;

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('曲库是空的'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('专辑页从会话取数显示专辑', (tester) async {
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
      sessionOverrides(transport),
    ));
    await tester.pumpAndSettle();

    expect(find.text('叶惠美'), findsOneWidget);
    expect(find.text('范特西'), findsOneWidget);
  });

  testWidgets('歌手列表页从会话取数显示歌手', (tester) async {
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
      sessionOverrides(transport),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Adele'), findsOneWidget);
    expect(find.text('3 张专辑'), findsOneWidget);
  });

  testWidgets('空曲库显示空态文案而不是空白', (tester) async {
    final transport = FakeTransport()..ok('search3.view');

    await tester.pumpWidget(harness(
      const SongsPage(),
      sessionOverrides(transport),
    ));
    await tester.pumpAndSettle();

    expect(find.text('曲库是空的'), findsOneWidget);
  });
}

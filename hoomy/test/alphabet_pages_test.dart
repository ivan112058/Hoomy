import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/shared/alphabet_index_bar.dart';
import 'package:hoomy/features/shared/alphabet_sectioned_view.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/songs/songs_page.dart';

import 'fake_transport.dart';

/// 字母分组与本地搜索在页面上的行为（票据 04）。
///
/// 分组键本身的规则在 `alphabet_index_test.dart` 里覆盖；这里只看界面：
/// 分组头、A–Z 快捷栏的出现与跳转、搜索即时过滤与清空恢复。
void main() {
  Widget harness(Widget page, List<Override> overrides) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: page),
      );

  /// 构造歌曲响应。[titles] 决定每首歌的分组键。
  List<Map<String, Object>> songsOf(List<String> titles) => [
        for (var i = 0; i < titles.length; i++)
          {'id': 's$i', 'title': titles[i], 'artist': '某歌手', 'album': '某专辑'},
      ];

  /// 60 首歌曲，落在 Q / W / Z 三组，各 20 首 —— 撑出多屏列表。
  final manySongs = songsOf([
    for (var i = 0; i < 20; i++) '晴$i',
    for (var i = 0; i < 20; i++) '五$i',
    for (var i = 0; i < 20; i++) '周$i',
  ]);

  group('歌曲页分组', () {
    testWidgets('按拼音首字母插入分组头', (tester) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '晴天'},
              {'id': 's2', 'title': 'Bohemian Rhapsody'},
              {'id': 's3', 'title': '以父之名'},
            ],
          },
        });

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pumpAndSettle();

      // 分组键：B（Bohemian）、Q（晴天）、Y（以父之名）。
      expect(
        tester
            .widgetList<SectionHeader>(find.byType(SectionHeader))
            .map((h) => h.title)
            .toList(),
        ['B', 'Q', 'Y'],
      );
      expect(find.text('晴天'), findsOneWidget);
    });

    testWidgets('曲库较小时不显示 A–Z 快捷栏', (tester) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {'id': 's1', 'title': '晴天'},
              {'id': 's2', 'title': '以父之名'},
            ],
          },
        });

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AlphabetIndexBar), findsNothing);
    });
  });

  group('歌曲页搜索', () {
    Future<FakeTransport> pumpSongs(WidgetTester tester) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': [
              {
                'id': 's1',
                'title': '晴天',
                'artist': '周杰伦',
                'album': '叶惠美',
              },
              {
                'id': 's2',
                'title': 'Bohemian Rhapsody',
                'artist': 'Queen',
                'album': 'A Night at the Opera',
              },
              {
                'id': 's3',
                'title': '以父之名',
                'artist': '周杰伦',
                'album': '叶惠美',
              },
            ],
          },
        });

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pumpAndSettle();
      return transport;
    }

    testWidgets('输入即按歌名过滤，大小写不敏感，且不发请求', (tester) async {
      final transport = await pumpSongs(tester);
      final requestsBefore = transport.requests.length;

      await tester.enterText(find.byType(TextField), 'bohemian');
      await tester.pump();

      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('晴天'), findsNothing);
      expect(find.text('以父之名'), findsNothing);
      expect(transport.requests.length, requestsBefore,
          reason: '搜索只在已取回的本地数据上过滤（ADR-0005）');
    });

    testWidgets('歌手与专辑也参与匹配', (tester) async {
      await pumpSongs(tester);

      await tester.enterText(find.byType(TextField), '叶惠美');
      await tester.pump();

      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);
      expect(find.text('Bohemian Rhapsody'), findsNothing);
    });

    testWidgets('无匹配显示空态；清空搜索词恢复完整分组列表', (tester) async {
      await pumpSongs(tester);

      await tester.enterText(find.byType(TextField), '不存在的歌');
      await tester.pump();
      expect(find.text('没有匹配的歌曲'), findsOneWidget);
      expect(find.byType(SectionHeader), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('没有匹配的歌曲'), findsNothing);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('以父之名'), findsOneWidget);
      expect(find.byType(SectionHeader), findsNWidgets(3));
    });
  });

  group('A–Z 快捷栏', () {
    Future<CustomScrollView> pumpManySongs(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {'song': manySongs},
        });

      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pumpAndSettle();
      return tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    }

    testWidgets('曲库较大时显示，按下即跳到对应分组', (tester) async {
      final scrolled = await pumpManySongs(tester);
      expect(find.byType(AlphabetIndexBar), findsOneWidget);

      final controller = scrolled.controller!;
      expect(controller.offset, 0);

      // 跳到第三组（Z）：前面是 Q、W 两组，每组「组头 + 20 行」。
      await tester.tap(find.byKey(const ValueKey('alphabet-index-Z')));
      await tester.pump();

      final expectedOffset =
          2 * (kSectionHeaderExtent + 20 * kHoomyListRowExtent);
      expect(controller.offset, closeTo(expectedOffset, 0.01));
    });

    testWidgets('点没有内容的字母组不改变位置', (tester) async {
      final scrolled = await pumpManySongs(tester);
      final controller = scrolled.controller!;

      await tester.tap(find.byKey(const ValueKey('alphabet-index-Z')));
      await tester.pump();
      final afterJump = controller.offset;

      // Q/W/Z 之外没有内容：B 组淡显且点了不跳。
      await tester.tap(find.byKey(const ValueKey('alphabet-index-B')));
      await tester.pump();

      expect(controller.offset, afterJump);
    });

    testWidgets('滚到后面的分组时，顶部不堆叠前面的组头', (tester) async {
      await pumpManySongs(tester);

      await tester.tap(find.byKey(const ValueKey('alphabet-index-Z')));
      await tester.pump();

      // pinned SliverPersistentHeader 会把过去的组头全留在顶部叠成一摞，
      // 因此组头只随内容滚动：视口内只应有当前分组的头。
      expect(
        tester
            .widgetList<SectionHeader>(find.byType(SectionHeader))
            .map((header) => header.title),
        ['Z'],
      );
    });

    Future<void> pumpWith(WidgetTester tester, int count) async {
      final transport = FakeTransport()
        ..ok('search3.view', {
          'searchResult3': {
            'song': manySongs.take(count).toList(),
          },
        });
      await tester.pumpWidget(harness(
        const SongsPage(),
        sessionOverrides(transport),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('低于条目数阈值不显示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpWith(tester, kAlphabetIndexBarMinItems - 1);
      expect(find.byType(AlphabetIndexBar), findsNothing);
    });

    testWidgets('达到条目数阈值即显示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpWith(tester, kAlphabetIndexBarMinItems);
      expect(find.byType(AlphabetIndexBar), findsOneWidget);
    });
  });

  testWidgets('专辑页按专辑名分组并带快捷栏', (tester) async {
    final transport = FakeTransport()
      ..ok('getAlbumList2.view', {
        'albumList2': {
          'album': [
            for (var i = 0; i < 10; i++)
              {'id': 'a$i', 'name': '八度空间$i', 'artist': '周杰伦'},
            for (var i = 0; i < 10; i++)
              {'id': 'b$i', 'name': '范特西$i', 'artist': '周杰伦'},
          ],
        },
      });

    await tester.pumpWidget(harness(
      const AlbumsPage(),
      sessionOverrides(transport),
    ));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SectionHeader>(find.byType(SectionHeader).first).title,
      'B',
    );
    expect(find.byType(AlphabetIndexBar), findsOneWidget);
  });

  testWidgets('专辑页快捷栏跳转后目标分组停在列表顶部', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 三组各 20 张，目标组不在末尾，跳转不会被 maxScrollExtent 夹住。
    final transport = FakeTransport()
      ..ok('getAlbumList2.view', {
        'albumList2': {
          'album': [
            for (var i = 0; i < 20; i++)
              {'id': 'b$i', 'name': '八度空间$i', 'artist': '周杰伦'},
            for (var i = 0; i < 20; i++)
              {'id': 'f$i', 'name': '范特西$i', 'artist': '周杰伦'},
            for (var i = 0; i < 20; i++)
              {'id': 'y$i', 'name': '叶惠美$i', 'artist': '周杰伦'},
          ],
        },
      });

    await tester.pumpWidget(harness(
      const AlbumsPage(),
      sessionOverrides(transport),
    ));
    await tester.pumpAndSettle();

    // 跳转前最后一组还没构建，找不到它的组头。
    Finder targetHeader() => find.byWidgetPredicate(
        (widget) => widget is SectionHeader && widget.title == 'Y');
    expect(targetHeader(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('alphabet-index-Y')));
    await tester.pump();

    expect(targetHeader(), findsOneWidget);
    expect(find.text('叶惠美0'), findsOneWidget);
    // 组头随内容滚动：跳转后它正好停在列表顶部，不在中间也不被上一组压住。
    expect(
      tester.getTopLeft(targetHeader()).dy,
      closeTo(tester.getTopLeft(find.byType(CustomScrollView)).dy, 1),
    );
  });

  testWidgets('歌手页按歌手名分组并带快捷栏', (tester) async {
    final transport = FakeTransport()
      ..ok('getArtists.view', {
        'artists': {
          'index': [
            {
              'name': 'A',
              'artist': [
                for (var i = 0; i < 20; i++)
                  {'id': 'ar$i', 'name': 'Adele$i', 'albumCount': 1},
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

    expect(
      tester.widget<SectionHeader>(find.byType(SectionHeader).first).title,
      'A',
    );
    expect(find.byType(AlphabetIndexBar), findsOneWidget);
  });
}

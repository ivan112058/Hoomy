import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/theme/hoomy_theme.dart';
import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/repositories/album_repository.dart';
import 'package:hoomy/data/repositories/artist_repository.dart';
import 'package:hoomy/data/repositories/repository_providers.dart';
import 'package:hoomy/data/repositories/song_repository.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/albums/albums_page.dart';
import 'package:hoomy/features/artists/artists_page.dart';
import 'package:hoomy/features/shared/cover_art.dart';
import 'package:hoomy/features/shared/hoomy_list_row.dart';
import 'package:hoomy/features/shared/song_tile.dart';
import 'package:hoomy/features/songs/songs_page.dart';
import 'package:hoomy/main.dart';

import 'fake_transport.dart';

/// 页面级视觉约定：行是 [HoomyListRow]、分隔线整宽 0.67dp、
/// 专辑网格固定 3 列、歌曲副标题为「歌手 - 专辑」且不带封面缩略图。
void main() {
  Widget harness(Widget page, List<Override> overrides) => ProviderScope(
        overrides: [
          subsonicClientProvider.overrideWithValue(null),
          ...overrides,
        ],
        child: MaterialApp(theme: hoomyLightTheme(), home: page),
      );

  SubsonicSong song({
    String id = 's1',
    String title = '晴天',
    String? artist = '周杰伦',
    String? album = '叶惠美',
    int? durationSec = 269,
  }) =>
      SubsonicSong(
        id: id,
        title: title,
        artist: artist,
        album: album,
        durationSec: durationSec,
      );

  testWidgets('歌曲行副标题为「歌手 - 专辑」，时长 13sp 加粗，不含封面缩略图', (tester) async {
    await tester.pumpWidget(harness(
      Scaffold(body: SongTile(song: song())),
      const [],
    ));

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦 - 叶惠美'), findsOneWidget);
    expect(find.byType(CoverArt), findsNothing);
    expect(find.byType(Image), findsNothing);

    final duration = tester.widget<Text>(find.text('4:29'));
    expect(duration.style?.fontSize, 13);
    expect(duration.style?.fontWeight, FontWeight.bold);
    expect(tester.getSize(find.byType(HoomyListRow)).height, 60);
  });

  testWidgets('歌曲只有歌手时副标题就是歌手，不留下空分隔符', (tester) async {
    await tester.pumpWidget(harness(
      Scaffold(body: SongTile(song: song(artist: '周杰伦', album: null))),
      const [],
    ));

    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.textContaining(' - '), findsNothing);
  });

  testWidgets('歌曲列表行行使用直角行、分隔线整宽无缩进', (tester) async {
    final transport = FakeTransport()
      ..ok('search3.view', {
        'searchResult3': {
          'song': [
            {'id': 's1', 'title': '晴天'},
            {'id': 's2', 'title': '以父之名'},
            {'id': 's3', 'title': '东风破'},
          ],
        },
      });

    await tester.pumpWidget(harness(
      const SongsPage(),
      [songRepositoryProvider.overrideWithValue(SongRepository(fakeClient(transport)))],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(HoomyListRow), findsNWidgets(3));

    final dividers = find.byType(Divider);
    expect(dividers, findsNWidgets(2));
    final listWidth = tester.getSize(find.byType(ListView)).width;
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(dividers.at(i)).width, listWidth, reason: '分隔线整宽无缩进');
      expect(tester.getSize(dividers.at(i)).height, 0.67);
    }
  });

  testWidgets('深色下封面占位用较高表面，不出现白块', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [subsonicClientProvider.overrideWithValue(null)],
      child: MaterialApp(
        theme: hoomyDarkTheme(),
        home: const Scaffold(body: CoverArt(coverArtId: 'c1')),
      ),
    ));

    final placeholder = tester.widget<Container>(find.byType(Container));
    expect(placeholder.color, HoomyColors.darkSurfaceRaised);
  });

  testWidgets('歌手列表行行使用直角行', (tester) async {    final transport = FakeTransport()
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

    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(HoomyListRow), findsOneWidget);
    expect(find.text('Adele'), findsOneWidget);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('专辑网格固定 3 列、封面 1:1 无圆角（屏宽 ${width.toInt()}）', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transport = FakeTransport()
        ..ok('getAlbumList2.view', {
          'albumList2': {
            'album': [
              {'id': 'al1', 'name': '叶惠美', 'artist': '周杰伦'},
              {'id': 'al2', 'name': '范特西', 'artist': '周杰伦'},
              {'id': 'al3', 'name': '八度空间', 'artist': '周杰伦'},
            ],
          },
        });

      await tester.pumpWidget(harness(
        const AlbumsPage(),
        [albumRepositoryProvider.overrideWithValue(AlbumRepository(fakeClient(transport)))],
      ));
      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(find.byType(ClipRRect), findsNothing, reason: '封面直角');

      final cover = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(cover.aspectRatio, 1);
    });
  }

  testWidgets('浅色为默认、深色跟随系统', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'navidrome_credentials':
          '{"serverUrl":"http://localhost:4533","username":"u","password":"p"}',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [subsonicClientProvider.overrideWithValue(null)],
        child: const HoomyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme?.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(app.darkTheme?.scaffoldBackgroundColor, const Color(0xFF25282D));
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/lyrics/song_lyrics.dart';
import 'package:hoomy/data/repositories/lyrics_repository.dart';

import 'fake_transport.dart';

/// 歌词取数：档位来自协议层解析，仓库负责按曲目缓存解析后的结构（ADR-0004）。
void main() {
  test('解析成领域模型并判定档位', () async {
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

    final lyrics = await LyricsRepository(fakeClient(transport))
        .lyricsFor(songId: 's1');

    expect(lyrics, isNotNull);
    expect(lyrics!.tier, LyricTier.line);
    expect(lyrics.lines.map((l) => l.text), ['第一行', '第二行']);
    expect(transport.requests, hasLength(1));
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
    final repository = LyricsRepository(fakeClient(transport));

    final first = await repository.lyricsFor(songId: 's1');
    final second = await repository.lyricsFor(songId: 's1');

    expect(identical(first, second), isTrue);
    expect(transport.requests, hasLength(1));
  });

  test('没有歌词时返回 null，并把「没有」也缓存下来', () async {
    final transport = FakeTransport()
      ..ok('getLyricsBySongId.view')
      ..ok('getLyrics.view');
    final repository = LyricsRepository(fakeClient(transport));

    expect(await repository.lyricsFor(songId: 's1'), isNull);
    expect(await repository.lyricsFor(songId: 's1'), isNull);

    // 结构化 + 纯文本各一次，第二次调用走缓存。
    expect(transport.requests, hasLength(2));
  });

  test('结构化无结果时回退纯文本，档位为纯文本', () async {
    final transport = FakeTransport()
      ..ok('getLyricsBySongId.view')
      ..ok('getLyrics.view', {
        'lyrics': {'value': '第一行\n第二行'},
      });

    final lyrics = await LyricsRepository(fakeClient(transport))
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
    final repository = LyricsRepository(fakeClient(transport));

    await repository.lyricsFor(songId: 's1');
    await repository.lyricsFor(songId: 's2');

    expect(transport.requests, hasLength(2));
    expect(transport.requests.first.uri.queryParameters['id'], 's1');
    expect(transport.lastQuery['id'], 's2');
  });

  test('失败的取数不缓存，重试会重新请求', () async {
    final transport = FakeTransport()
      ..fail('getLyricsBySongId.view', 40, 'Wrong username or password');
    final repository = LyricsRepository(fakeClient(transport));

    await expectLater(repository.lyricsFor(songId: 's1'), throwsA(anything));
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
    final lyrics = await repository.lyricsFor(songId: 's1');

    expect(lyrics!.lines.single.text, '重试成功');
    expect(transport.requests, hasLength(2));
  });
}

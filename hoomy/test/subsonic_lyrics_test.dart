import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/subsonic/subsonic_client.dart';

import 'fake_transport.dart';

/// S1 接缝：歌词解析。既有缺陷（结构化歌词解析路径错误、getLyrics 读错字段）
/// 都落在这条链路上，这里用固定响应锁死。
void main() {
  group('结构化歌词（getLyricsBySongId）', () {
    test('回归：从 lyricsList.structuredLyrics 取值，并解析出带 start 的行', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'displayArtist': '周杰伦',
                'displayTitle': '晴天',
                'synced': true,
                'line': [
                  {'start': 0, 'value': '故事的小黄花'},
                  {'start': 4200, 'value': '从出生那年就飘着'},
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics, isNotNull);
      expect(lyrics!.synced, isTrue);
      expect(lyrics.artist, '周杰伦');
      expect(lyrics.title, '晴天');
      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines.first.startMs, 0);
      expect(lyrics.lines.first.value, '故事的小黄花');
      expect(lyrics.lines[1].startMs, 4200);
      expect(lyrics.lines[1].value, '从出生那年就飘着');

      // 必须请求结构化端点，且显式请求 v2 词级时间轴。
      expect(transport.lastEndpoint, 'getLyricsBySongId.view');
      expect(transport.lastQuery['id'], 's1');
      expect(transport.lastQuery['enhanced'], 'true');
    });

    test('解析 offset（LRC 的 [offset:]），缺省为 0', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'offset': -350,
                'line': [
                  {'start': 1000, 'value': '第一行'},
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics!.offsetMs, -350);

      // 服务端不返回 offset 时视为 0。
      final noOffset = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'line': [
                  {'start': 1000, 'value': '第一行'},
                ],
              },
            ],
          },
        });
      expect(
        (await fakeClient(noOffset).getStructuredLyrics('s1'))!.offsetMs,
        0,
      );
    });

    test('逐字档：解析 cueLine/cue 与 UTF-8 字节闭区间', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'line': [
                  {'start': 0, 'value': '故事的小黄花'},
                ],
                'cueLine': [
                  {
                    'index': 0,
                    'start': 0,
                    'end': 2000,
                    'value': '故事的小黄花',
                    'agentId': 'main',
                    'cue': [
                      {
                        'start': 0,
                        'end': 1000,
                        'byteStart': 0,
                        'byteEnd': 8,
                        'value': '故事的',
                      },
                      {
                        'start': 1000,
                        'end': 2000,
                        'byteStart': 9,
                        'byteEnd': 17,
                        'value': '小黄花',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics!.cueLines, hasLength(1));
      final cueLine = lyrics.cueLines.single;
      expect(cueLine.index, 0);
      expect(cueLine.startMs, 0);
      expect(cueLine.endMs, 2000);
      expect(cueLine.value, '故事的小黄花');
      expect(cueLine.agentId, 'main');
      expect(cueLine.cues, hasLength(2));
      expect(cueLine.cues.first.value, '故事的');
      expect(cueLine.cues.first.byteStart, 0);
      expect(cueLine.cues.first.byteEnd, 8);

      // 字节区间是 0 基闭区间，按 UTF-8 字节切片才不错位（ADR-0004）。
      final lineBytes = utf8.encode(cueLine.value);
      for (final cue in cueLine.cues) {
        expect(
          utf8.decode(lineBytes.sublist(cue.byteStart!, cue.byteEnd! + 1)),
          cue.value,
        );
      }
    });

    test('逐行档：只有 line[].start，没有词级时间轴', () async {
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

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics!.lines, hasLength(2));
      expect(lyrics.lines.every((l) => l.startMs != null), isTrue);
      expect(lyrics.cueLines, isEmpty);
    });

    test('纯文本档：line 无 start，synced=false', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': false,
                'line': [
                  {'value': '第一行'},
                  {'value': '第二行'},
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics!.synced, isFalse);
      expect(lyrics.lines.map((l) => l.value), ['第一行', '第二行']);
      expect(lyrics.lines.every((l) => l.startMs == null), isTrue);
      expect(lyrics.cueLines, isEmpty);
    });

    test('多语言歌词只取主歌词（kind=main），不取翻译', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'kind': 'translation',
                'synced': false,
                'line': [
                  {'value': 'translated line'},
                ],
              },
              {
                'kind': 'main',
                'synced': false,
                'line': [
                  {'value': '主歌词'},
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport).getStructuredLyrics('s1');

      expect(lyrics!.lines.single.value, '主歌词');
    });

    test('structuredLyrics 为空时返回 null', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {'structuredLyrics': <Object>[]},
        });

      expect(await fakeClient(transport).getStructuredLyrics('s1'), isNull);
    });

    test('响应里没有 lyricsList 时返回 null', () async {
      final transport = FakeTransport()..ok('getLyricsBySongId.view');

      expect(await fakeClient(transport).getStructuredLyrics('s1'), isNull);
    });

    test('服务端不认识该端点（error 70）时返回 null，交给上层回退', () async {
      final transport = FakeTransport()
        ..fail(
          'getLyricsBySongId.view',
          70,
          'The requested data was not found',
        );

      expect(await fakeClient(transport).getStructuredLyrics('s1'), isNull);
    });

    test('其它 Subsonic 错误照常抛出，不被当成「没有歌词」', () async {
      final transport = FakeTransport()
        ..fail('getLyricsBySongId.view', 40, 'Wrong username or password');

      await expectLater(
        fakeClient(transport).getStructuredLyrics('s1'),
        throwsA(isA<SubsonicException>().having((e) => e.code, 'code', 40)),
      );
    });
  });

  group('纯文本歌词（getLyrics）', () {
    test('回归：读取 lyrics.value 字段并按行拆分，不带时间轴', () async {
      final transport = FakeTransport()
        ..ok('getLyrics.view', {
          'lyrics': {
            'artist': '周杰伦',
            'title': '晴天',
            'value': '故事的小黄花\n从出生那年就飘着',
          },
        });

      final lyrics = await fakeClient(transport)
          .getLyrics(artist: '周杰伦', title: '晴天');

      expect(lyrics, isNotNull);
      expect(lyrics!.synced, isFalse);
      expect(lyrics.lines.map((l) => l.value), ['故事的小黄花', '从出生那年就飘着']);
      expect(lyrics.lines.every((l) => l.startMs == null), isTrue);
      expect(transport.lastQuery['artist'], '周杰伦');
      expect(transport.lastQuery['title'], '晴天');
    });

    test('文本只有空白时返回 null', () async {
      final transport = FakeTransport()
        ..ok('getLyrics.view', {
          'lyrics': {'value': '   '},
        });

      expect(
        await fakeClient(transport).getLyrics(artist: 'a', title: 't'),
        isNull,
      );
    });

    test('没有歌词字段时返回 null', () async {
      final transport = FakeTransport()..ok('getLyrics.view');

      expect(
        await fakeClient(transport).getLyrics(artist: 'a', title: 't'),
        isNull,
      );
    });
  });

  group('歌词回退（getLyricsForSong）', () {
    test('结构化有结果时不请求纯文本端点', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view', {
          'lyricsList': {
            'structuredLyrics': [
              {
                'synced': true,
                'line': [
                  {'start': 0, 'value': '第一行'},
                ],
              },
            ],
          },
        });

      final lyrics = await fakeClient(transport)
          .getLyricsForSong(songId: 's1', artist: '周杰伦', title: '晴天');

      expect(lyrics!.lines.single.value, '第一行');
      expect(transport.requests, hasLength(1));
    });

    test('结构化无结果时回退纯文本', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view', {
          'lyrics': {'value': '第一行\n第二行'},
        });

      final lyrics = await fakeClient(transport)
          .getLyricsForSong(songId: 's1', artist: '周杰伦', title: '晴天');

      expect(lyrics, isNotNull);
      expect(lyrics!.synced, isFalse);
      expect(lyrics.lines.map((l) => l.value), ['第一行', '第二行']);
      expect(transport.requests, hasLength(2));
      expect(
        transport.requests.first.uri.pathSegments.last,
        'getLyricsBySongId.view',
      );
      expect(transport.lastEndpoint, 'getLyrics.view');
    });

    test('服务端不认识结构化端点时回退纯文本', () async {
      final transport = FakeTransport()
        ..fail('getLyricsBySongId.view', 70, 'not found')
        ..ok('getLyrics.view', {
          'lyrics': {'value': '纯文本歌词'},
        });

      final lyrics = await fakeClient(transport)
          .getLyricsForSong(songId: 's1', artist: '周杰伦', title: '晴天');

      expect(lyrics!.lines.single.value, '纯文本歌词');
      expect(transport.lastEndpoint, 'getLyrics.view');
    });

    test('两者都无时返回 null（界面呈现「暂无歌词」）', () async {
      final transport = FakeTransport()
        ..ok('getLyricsBySongId.view')
        ..ok('getLyrics.view');

      final lyrics = await fakeClient(transport)
          .getLyricsForSong(songId: 's1', artist: '周杰伦', title: '晴天');

      expect(lyrics, isNull);
      expect(transport.requests, hasLength(2));
    });
  });
}

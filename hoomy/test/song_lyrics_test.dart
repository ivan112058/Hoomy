import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/lyrics/song_lyrics.dart';
import 'package:hoomy/data/subsonic/models.dart';

/// 歌词档位判定与 UTF-8 字节区间切片（票据 10 / ADR-0004）。
///
/// 这一层是纯 Dart：不碰界面、不碰网络，档位由内容决定，字节切片必须
/// 按字节而不是字符下标，否则中文歌词错位。
void main() {
  SubsonicLyrics plainLyrics() => const SubsonicLyrics(
    synced: false,
    lines: [
      SubsonicLyricLine(value: '第一行'),
      SubsonicLyricLine(value: '第二行'),
    ],
  );

  SubsonicLyrics lineLyrics() => const SubsonicLyrics(
    synced: true,
    lines: [
      SubsonicLyricLine(startMs: 0, value: '第一行'),
      SubsonicLyricLine(startMs: 1500, value: '第二行'),
      SubsonicLyricLine(startMs: 3000, value: '第三行'),
    ],
  );

  SubsonicLyrics wordLyrics() => const SubsonicLyrics(
    synced: true,
    lines: [SubsonicLyricLine(startMs: 0, value: '故事的小黄花')],
    cueLines: [
      SubsonicCueLine(
        index: 0,
        startMs: 0,
        endMs: 2000,
        value: '故事的小黄花',
        cues: [
          SubsonicCue(
            startMs: 0,
            endMs: 1000,
            byteStart: 0,
            byteEnd: 8,
            value: '故事的',
          ),
          SubsonicCue(
            startMs: 1000,
            endMs: 2000,
            byteStart: 9,
            byteEnd: 17,
            value: '小黄花',
          ),
        ],
      ),
    ],
  );

  group('档位判定', () {
    test('无时间轴的纯文本是 plain 档', () {
      final lyrics = SongLyrics.fromSubsonic(plainLyrics());

      expect(lyrics.tier, LyricTier.plain);
      expect(lyrics.lines.map((l) => l.text), ['第一行', '第二行']);
      expect(lyrics.lines.every((l) => l.start == null), isTrue);
    });

    test('仅行级 start 是 line 档', () {
      final lyrics = SongLyrics.fromSubsonic(lineLyrics());

      expect(lyrics.tier, LyricTier.line);
      expect(lyrics.lines.first.start, Duration.zero);
      expect(lyrics.lines[1].start, const Duration(milliseconds: 1500));
    });

    test('带词级字节区间是 word 档，行文本与 cue 都保留', () {
      final lyrics = SongLyrics.fromSubsonic(wordLyrics());

      expect(lyrics.tier, LyricTier.word);
      final line = lyrics.lines.single;
      expect(line.text, '故事的小黄花');
      expect(line.cues, hasLength(2));
      expect(line.cues.first.byteStart, 0);
      expect(line.cues.first.byteEnd, 8);
    });

    test('cueLine 缺 value 时按 index 回退到 line 文本', () {
      const raw = SubsonicLyrics(
        synced: true,
        lines: [SubsonicLyricLine(startMs: 0, value: '第一行')],
        cueLines: [
          SubsonicCueLine(
            index: 0,
            startMs: 0,
            cues: [
              SubsonicCue(startMs: 0, byteStart: 0, byteEnd: 2, value: '第一'),
            ],
          ),
        ],
      );

      final lyrics = SongLyrics.fromSubsonic(raw);

      expect(lyrics.lines.single.text, '第一行');
    });

    test('cueLine 自己没有 start 时用首个 cue 的 start 兜底', () {
      const raw = SubsonicLyrics(
        synced: true,
        cueLines: [
          SubsonicCueLine(
            value: '第一行',
            cues: [
              SubsonicCue(startMs: 500, byteStart: 0, byteEnd: 2, value: '第一'),
            ],
          ),
        ],
      );

      final lyrics = SongLyrics.fromSubsonic(raw);

      expect(lyrics.lines.single.start, const Duration(milliseconds: 500));
      expect(lyrics.tier, LyricTier.word);
    });

    test('cueLine 存在但没有可用字节区间时降为 line 档', () {
      const raw = SubsonicLyrics(
        synced: true,
        cueLines: [SubsonicCueLine(index: 0, startMs: 0, value: '第一行')],
      );

      final lyrics = SongLyrics.fromSubsonic(raw);

      expect(lyrics.tier, LyricTier.line);
    });

    test('只有部分行带词级时间轴时，不丢掉其余行', () {
      const raw = SubsonicLyrics(
        synced: true,
        lines: [
          SubsonicLyricLine(startMs: 0, value: '第一行'),
          SubsonicLyricLine(startMs: 1000, value: '第二行'),
          SubsonicLyricLine(startMs: 2000, value: '第三行'),
        ],
        cueLines: [
          SubsonicCueLine(
            index: 1,
            startMs: 1000,
            value: '第二行',
            cues: [
              SubsonicCue(
                startMs: 1000,
                byteStart: 0,
                byteEnd: 8,
                value: '第二行',
              ),
            ],
          ),
        ],
      );

      final lyrics = SongLyrics.fromSubsonic(raw);

      expect(lyrics.tier, LyricTier.word);
      expect(lyrics.lines.map((l) => l.text), ['第一行', '第二行', '第三行']);
      expect(lyrics.lines[0].cues, isEmpty);
      expect(lyrics.lines[1].cues, hasLength(1));
      expect(lyrics.lines[2].cues, isEmpty);
      expect(lyrics.lines[2].start, const Duration(milliseconds: 2000));
    });
  });

  group('当前行判定', () {
    test('按位置落在最后一个已开始的行上', () {
      final lyrics = SongLyrics.fromSubsonic(lineLyrics());

      expect(lyrics.activeLineIndex(Duration.zero), 0);
      expect(lyrics.activeLineIndex(const Duration(milliseconds: 1499)), 0);
      expect(lyrics.activeLineIndex(const Duration(milliseconds: 1500)), 1);
      expect(lyrics.activeLineIndex(const Duration(seconds: 99)), 2);
    });

    test('第一行尚未开始时没有当前行', () {
      const raw = SubsonicLyrics(
        synced: true,
        lines: [SubsonicLyricLine(startMs: 1000, value: '第一行')],
      );

      final lyrics = SongLyrics.fromSubsonic(raw);

      expect(lyrics.activeLineIndex(const Duration(milliseconds: 500)), isNull);
    });

    test('纯文本没有时间轴，永远没有当前行', () {
      final lyrics = SongLyrics.fromSubsonic(plainLyrics());

      expect(lyrics.activeLineIndex(const Duration(seconds: 30)), isNull);
    });
  });

  group('UTF-8 字节区间切片', () {
    test('中文逐字：闭区间按字节切片，不错位', () {
      // 「故事的」= 3 个汉字 × 3 字节，闭区间 [0, 8]。
      expect(utf8Slice('故事的小黄花', 0, 8), '故事的');
      // 「小黄花」= [9, 17]。
      expect(utf8Slice('故事的小黄花', 9, 17), '小黄花');
    });

    test('中英混排：ASCII 与汉字都按字节', () {
      const text = 'Hello 世界';
      expect(utf8Slice(text, 0, 4), 'Hello');
      expect(utf8Slice(text, 6, 11), '世界');
    });

    test('区间端点落在多字节字符内部时收敛到完整字符', () {
      // 「世界」：世 = [0,2]，界 = [3,5]。
      expect(utf8Slice('世界', 1, 1), '世');
      expect(utf8Slice('世界', 0, 1), '世');
      expect(utf8Slice('世界', 2, 3), '世界');
    });

    test('越界区间被收敛，不抛异常', () {
      expect(utf8Slice('世界', -5, 100), '世界');
      expect(utf8Slice('世界', 4, 2), '');
    });
  });

  group('已唱前缀（逐字高亮）', () {
    test('按位置返回已唱部分的字符长度', () {
      final lyrics = SongLyrics.fromSubsonic(wordLyrics());
      final line = lyrics.lines.single;

      // 位置 0：第一个 cue（字节 [0,8] → 3 个字）。
      expect(lyrics.sungPrefixLength(line, Duration.zero), 3);
      // 位置 1000ms：第二个 cue 已开始（字节 [9,17] → 整行 6 个字）。
      expect(
        lyrics.sungPrefixLength(line, const Duration(milliseconds: 1000)),
        6,
      );
      expect(lyrics.sungPrefixLength(line, const Duration(seconds: 5)), 6);
    });

    test('位置在第一个 cue 之前时没有已唱部分', () {
      final lyrics = SongLyrics.fromSubsonic(wordLyrics());
      final line = lyrics.lines.single;

      expect(lyrics.sungPrefixLength(line, const Duration(seconds: -1)), 0);
    });

    test('行没有 cue 时没有已唱部分', () {
      final lyrics = SongLyrics.fromSubsonic(lineLyrics());

      expect(
        lyrics.sungPrefixLength(lyrics.lines.first, const Duration(seconds: 9)),
        0,
      );
    });
  });
}

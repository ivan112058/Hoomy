import 'dart:convert';

import '../subsonic/models.dart';

/// 歌词档位：按**内容可用性**呈现歌词的三种形态（`CONTEXT.md`「歌词档位」，
/// ADR-0004）。档位由服务端返回的歌词内容决定，不由服务端版本决定。
enum LyricTier {
  /// 纯文本：没有时间轴，静态呈现，不自动滚动。
  plain,

  /// 逐行：只有行级 `start`，当前行高亮并居中自动跟随。
  line,

  /// 逐字：曲目自带词级时间轴，当前行内已唱部分高亮。
  word,
}

/// 逐字歌词里的一个「词」。
///
/// [byteStart]/[byteEnd] 是所属行文本的 0 基**闭区间 UTF-8 字节**偏移，
/// 切片必须按字节而不是字符下标，否则中文歌词错位（ADR-0004）。
class LyricCue {
  const LyricCue({this.start, this.byteStart, this.byteEnd});

  final Duration? start;
  final int? byteStart;
  final int? byteEnd;

  /// 是否带可用的字节区间：没有它就做不了逐字高亮。
  bool get hasByteRange => byteStart != null && byteEnd != null;
}

/// 解析后的一行歌词。
class LyricLine {
  const LyricLine({this.start, required this.text, this.cues = const []});

  final Duration? start;
  final String text;

  /// 词级时间轴；为空表示这一行只有行级时间轴（或不带时间轴）。
  final List<LyricCue> cues;
}

/// 解析后的歌词：档位在这里一次判定，界面只按档位渲染。
///
/// 与协议模型 [SubsonicLyrics] 的区别：协议模型贴着服务端字段，本模型是
/// 界面消费的领域结构（行文本 + 时间轴 + 档位）。解析只在取数时做一次，
/// 之后进出歌词态复用同一份结构（ADR-0004 决策 5）。
class SongLyrics {
  const SongLyrics({required this.tier, required this.lines});

  /// 从协议模型解析。
  ///
  /// 行级 `line` 给出行列表与行级时间轴；逐字 `cueLine` 按 `index`（缺省按位置）
  /// 贴回对应行，其文本优先展现（词级字节区间是对它量的）。只有 `cueLine` 而
  /// 没有 `line` 时才整体用 `cueLine` 建行 —— 这样「服务端只给部分行带词级
  /// 时间轴」也不会丢掉其余行。
  factory SongLyrics.fromSubsonic(SubsonicLyrics raw) {
    final lines = _mergeLines(raw);
    return SongLyrics(tier: _tierOf(lines), lines: lines);
  }

  final LyricTier tier;
  final List<LyricLine> lines;

  /// 当前行下标：最后一个已经开始（`start <= position`）的行；都没有时为 null。
  ///
  /// 不按行的结束时间收口 —— 常见 LRC 在间奏处留空档，按结束时间会让高亮闪烁。
  int? activeLineIndex(Duration position) {
    int? active;
    Duration? best;
    for (var i = 0; i < lines.length; i++) {
      final start = lines[i].start;
      if (start == null || start > position) continue;
      if (best == null || start >= best) {
        best = start;
        active = i;
      }
    }
    return active;
  }

  /// 当前行里「已经唱过」的部分占多少个字符（UTF-16 code unit）。
  ///
  /// 取所有 `start <= position` 的 cue 里最大的 `byteEnd`，按 UTF-8 字节闭区间
  /// `[0, byteEnd]` 切成前缀。正在唱的那个 cue **也**算已唱（卡拉OK 的惯例：
  /// 词一开口就跟着亮），返回 0 表示这一行还没开始唱（或没有词级时间轴）。
  int sungPrefixLength(LyricLine line, Duration position) {
    int? byteEnd;
    for (final cue in line.cues) {
      final start = cue.start;
      final end = cue.byteEnd;
      if (start == null || end == null) continue;
      if (start <= position && (byteEnd == null || end > byteEnd)) {
        byteEnd = end;
      }
    }
    if (byteEnd == null) return 0;
    return utf8Slice(line.text, 0, byteEnd).length;
  }

  /// 把行级歌词与逐字时间轴合并成一份行列表。
  static List<LyricLine> _mergeLines(SubsonicLyrics raw) {
    final offset = raw.offsetMs;
    final lines = _linesFromLines(raw.lines, offset);
    if (raw.cueLines.isEmpty) return lines;
    // 只有 cueLine、没有 line：cueLine 自带文本，直接用它建行。
    if (lines.isEmpty) {
      return [
        for (var i = 0; i < raw.cueLines.length; i++)
          _lineFromCue(raw.cueLines[i], null, offset),
      ];
    }
    final byIndex = <int, SubsonicCueLine>{};
    for (var i = 0; i < raw.cueLines.length; i++) {
      byIndex[raw.cueLines[i].index ?? i] = raw.cueLines[i];
    }
    return [
      for (var i = 0; i < lines.length; i++)
        _mergeCue(lines[i], byIndex[i], offset),
    ];
  }

  static List<LyricLine> _linesFromLines(
    List<SubsonicLyricLine> raw,
    int offsetMs,
  ) => [
    for (final line in raw)
      LyricLine(start: _ms(line.startMs, offsetMs), text: line.value),
  ];

  /// 把一条 [cueLine] 贴到行级歌词上；[base] 是行级歌词里的对应行。
  static LyricLine _mergeCue(
    LyricLine base,
    SubsonicCueLine? cue,
    int offsetMs,
  ) {
    if (cue == null) return base;
    final line = _lineFromCue(cue, base.text, offsetMs);
    return LyricLine(
      start: line.start ?? base.start,
      // 词级字节区间是对 cueLine.value 量的，文本与它一致才不会错位。
      text: line.text.isEmpty ? base.text : line.text,
      cues: line.cues,
    );
  }

  /// 从一条 `cueLine` 建行；[fallbackText] 是行级歌词里的对应文本。
  static LyricLine _lineFromCue(
    SubsonicCueLine raw,
    String? fallbackText,
    int offsetMs,
  ) {
    final cues = [
      for (final cue in raw.cues)
        LyricCue(
          start: _ms(cue.startMs, offsetMs),
          byteStart: cue.byteStart,
          byteEnd: cue.byteEnd,
        ),
    ];
    return LyricLine(
      // 少数服务端不给 cueLine.start，用首个 cue 的 start 兜底。
      start:
          _ms(raw.startMs, offsetMs) ??
          (cues.isEmpty ? null : cues.first.start),
      text: raw.value.isNotEmpty ? raw.value : (fallbackText ?? ''),
      cues: cues,
    );
  }

  /// 档位判定：有可用词级字节区间 → 逐字；否则有行级时间轴 → 逐行；
  /// 都没有 → 纯文本。
  static LyricTier _tierOf(List<LyricLine> lines) {
    if (lines.any((line) => line.cues.any((cue) => cue.hasByteRange))) {
      return LyricTier.word;
    }
    if (lines.any((line) => line.start != null)) return LyricTier.line;
    return LyricTier.plain;
  }
}

/// 歌词时间戳 → [Duration]，并套用条目的 [offsetMs]。
///
/// OpenSubsonic 的语义：**正 offset 表示歌词更早出现**，所以生效时间 =
/// `start - offset`（缺省 0）；偏移后为负的时间收敛到 0。
Duration? _ms(int? milliseconds, int offsetMs) => milliseconds == null
    ? null
    : Duration(milliseconds: (milliseconds - offsetMs).clamp(0, 1 << 62));

/// 按 UTF-8 字节闭区间 `[startByte, endByte]` 切出 [text] 的一段。
///
/// 端点落在多字节字符内部时**向外收敛到完整字符**：中文歌词因此不会切出
/// 半个字，也不会因为一个字节的偏差整体错位（ADR-0004）。越界端点被收敛
/// 到文本边界，区间颠倒时返回空串。
String utf8Slice(String text, int startByte, int endByte) {
  final bytes = utf8.encode(text);
  var start = startByte.clamp(0, bytes.length);
  var end = endByte.clamp(-1, bytes.length - 1);
  if (end < start) return '';
  // 起点落在延续字节上时往前退到该字符的首字节。
  while (start > 0 && (bytes[start] & 0xC0) == 0x80) {
    start--;
  }
  // 终点落在字符中间时往后补到该字符的末字节。
  while (end + 1 < bytes.length && (bytes[end + 1] & 0xC0) == 0x80) {
    end++;
  }
  return utf8.decode(bytes.sublist(start, end + 1));
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hoomy_theme.dart';
import '../../data/lyrics/song_lyrics.dart';
import '../../player/playback_controller.dart';
import '../shared/error_retry_view.dart';
import '../shared/hoomy_focusable.dart';

/// 歌词呈现：按内容档位渲染（`CONTEXT.md`「歌词档位」，ADR-0004）。
///
/// - **纯文本档**：静态列出，不自动滚动；
/// - **逐行档**：当前行高亮，列表居中自动跟随；
/// - **逐字档**：当前行内已唱部分高亮（按 UTF-8 字节闭区间切片）；
/// - **无歌词**：显示「暂无歌词」且不可滚动。
///
/// 点歌词区域切回封面（[onTap]）；歌词态所需的**屏幕常亮**开关不在本部件里，
/// 由播放页顶栏承载。
///
/// 歌词由播放页**预取**（ADR-0007）：本部件拿到的是已经取好的 [lyrics]，
/// 切到歌词态不再发起请求。
class LyricsView extends StatelessWidget {
  const LyricsView({
    super.key,
    required this.controller,
    required this.songId,
    required this.lyrics,
    required this.onTap,
    required this.onRetry,
  });

  final PlaybackController controller;

  /// 当前曲目 id；换歌时用它给列表换 key，避免残留上一首的滚动与高亮。
  final String songId;

  final AsyncValue<SongLyrics?> lyrics;

  /// 点歌词切回封面。
  final VoidCallback onTap;

  /// 取歌词失败后的重试。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    // 整块歌词区域可点/可聚焦：点任意一行、或在 TV 上按下确认键都切回封面，
    // 与「点封面切到歌词」对称。聚焦只画一圈外框，不铺底色 —— 铺蓝会把
    // 歌词文字淹没。
    return HoomyFocusable(
      onTap: onTap,
      builder: (context, highlight) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: highlight.highlighted
                ? palette.pressedBackground
                : Colors.transparent,
            width: 2,
          ),
        ),
        // 强制铺满：单行歌词（如「纯音乐」）时 `SingleChildScrollView` 在宽松
        // 约束下只占内容高度，不铺满的话可点区域会缩到那一行上，点空白没反应。
        child: SizedBox.expand(
          child: lyrics.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                ErrorRetryView(message: describeError(error), onRetry: onRetry),
            data: (data) => data == null || data.lines.isEmpty
                ? const _NoLyrics()
                : ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => _LyricsList(
                      // 换歌即换一份列表状态：不残留上一首的滚动位置与高亮行。
                      key: ValueKey(songId),
                      lyrics: data,
                      position: controller.session.position,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 无歌词：给出明确文案而不是空白，且**不可滚动**。
class _NoLyrics extends StatelessWidget {
  const _NoLyrics();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '暂无歌词',
        style: TextStyle(color: HoomyPalette.of(context).textSecondary),
      ),
    );
  }
}

/// 歌词列表：承载自动跟随与「手动滚动后暂停跟随」。
class _LyricsList extends StatefulWidget {
  const _LyricsList({super.key, required this.lyrics, required this.position});

  final SongLyrics lyrics;

  /// 当前播放位置；每 ~200ms 更新一次。
  final Duration position;

  @override
  State<_LyricsList> createState() => _LyricsListState();
}

class _LyricsListState extends State<_LyricsList> {
  /// 手动滚动后多久恢复自动跟随。
  static const resumeDelay = Duration(seconds: 3);

  /// 自动跟随的滚动时长。
  static const followDuration = Duration(milliseconds: 260);

  final _scroll = ScrollController();

  /// 每行一个 key：靠它把「当前行」滚到视口中央。
  late List<GlobalKey> _lineKeys;

  /// 上一次的当前行，仅用于「换了行才跟随」。
  int? _active;

  /// 是否处于自动跟随；用户手动滚动后暂停，[resumeDelay] 后恢复。
  bool _following = true;
  Timer? _resume;

  @override
  void initState() {
    super.initState();
    _lineKeys = _keysFor(widget.lyrics.lines.length);
    _active = widget.lyrics.activeLineIndex(widget.position);
    // 从曲目中途进入歌词态时，直接落在当前行上而不必等下一次进度通知。
    if (_active != null) _scheduleReveal(_active!);
  }

  @override
  void didUpdateWidget(covariant _LyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics.lines.length != widget.lyrics.lines.length) {
      _lineKeys = _keysFor(widget.lyrics.lines.length);
    }
    final next = widget.lyrics.activeLineIndex(widget.position);
    if (next != _active) {
      _active = next;
      if (_following && next != null) _scheduleReveal(next);
    }
  }

  @override
  void dispose() {
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<GlobalKey> _keysFor(int count) => [
    for (var i = 0; i < count; i++) GlobalKey(),
  ];

  /// 把某一行滚到视口中央。
  ///
  /// 放到帧后执行：`didUpdateWidget` 发生在构建期，此刻直接滚动会在构建期
  /// 触发滚动状态变更。
  void _scheduleReveal(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _lineKeys.length) return;
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext == null) return;
      Scrollable.ensureVisible(
        lineContext,
        // 居中：当前行落在视口中线，上下各留半屏看前后文。
        alignment: 0.5,
        duration: followDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _onScroll(ScrollNotification notification) {
    // 只认**用户发起**的滚动：自动跟随的 `ensureVisible` 动画不带 dragDetails，
    // 也不产生 forward/reverse 的 UserScrollNotification。
    final userScroll =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollEndNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle);
    // 拖动过程中每次更新都重置计时：手指还按着时不能恢复跟随，否则
    // `ensureVisible` 会在拖动中途把列表抢走。
    if (userScroll) _pauseFollow();
    return false;
  }

  /// 用户接管滚动：暂停跟随，[resumeDelay] 后自动恢复并重新对齐当前行。
  void _pauseFollow() {
    _resume?.cancel();
    if (_following) setState(() => _following = false);
    _resume = Timer(resumeDelay, () {
      if (!mounted) return;
      setState(() => _following = true);
      if (_active != null) _scheduleReveal(_active!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    // 当前行只在 [_active] 一处算：`didUpdateWidget` 已把位置变化落进来。
    final active = _active;
    return NotificationListener<ScrollNotification>(
      // 用户手动滚动即暂停自动跟随，超时后恢复。
      onNotification: _onScroll,
      // 刻意**不用** `ListView.builder`：懒构建时远处的行没有 RenderObject，
      // `ensureVisible` 找不到它，从曲目中段进入播放页（当前行在几十行开外）
      // 就无法居中。歌词行数有限，全量构建换取「任意行都能跳过去」。
      child: SingleChildScrollView(
        controller: _scroll,
        // 首尾留白：第一行与最后一行也能滚到视口中央。
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < lyrics.lines.length; index++)
              _LyricLineRow(
                key: _lineKeys[index],
                line: lyrics.lines[index],
                active: index == active,
                // 逐字高亮只算当前行；其它行不算，省掉逐行的字节换算。
                sungPrefixLength:
                    lyrics.tier == LyricTier.word && index == active
                    ? lyrics.sungPrefixLength(
                        lyrics.lines[index],
                        widget.position,
                      )
                    : 0,
              ),
          ],
        ),
      ),
    );
  }
}

/// 一行歌词。
///
/// 逐字档下，[sungPrefixLength] 大于 0 时把行文本切成「已唱 + 未唱」两段，
/// 已唱部分用播放态强调色。段的划分来自 [SongLyrics.sungPrefixLength]，
/// 按 UTF-8 字节闭区间换算，中文不会错位。
class _LyricLineRow extends StatelessWidget {
  const _LyricLineRow({
    super.key,
    required this.line,
    required this.active,
    required this.sungPrefixLength,
  });

  final LyricLine line;

  /// 是否是当前行。
  final bool active;

  /// 当前行里已唱部分的字符长度。
  final int sungPrefixLength;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final style = TextStyle(
      fontSize: HoomyDimens.listTitleFontSize,
      height: 1.6,
      // 当前行用歌词高亮色；其余行是次文字色，读起来有主次。
      color: active ? palette.lyricHighlight : palette.textSecondary,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );
    final sung = sungPrefixLength.clamp(0, line.text.length);
    final Widget text;
    if (active && sung > 0) {
      text = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: line.text.substring(0, sung),
              style: style.copyWith(color: palette.playing),
            ),
            TextSpan(text: line.text.substring(sung), style: style),
          ],
        ),
      );
    } else {
      text = Text(line.text, style: style);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: text,
    );
  }
}

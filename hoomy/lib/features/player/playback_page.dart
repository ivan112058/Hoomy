import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/screen/screen_awake.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/star/star_target.dart';
import '../../data/subsonic/models.dart';
import '../../player/playback_controller.dart';
import '../shared/cover_art.dart';
import '../shared/duration_text.dart';
import '../shared/song_secondary_text.dart';
import '../shared/star_button.dart';
import 'lyrics_view.dart';
import 'playback_controls.dart';
import 'playback_listenable.dart';
import 'queue_overlay.dart';

/// 全屏播放页的覆盖层路由：从迷你播放条展开。
///
/// 与层级页面（`MaterialPageRoute` 从右侧推入）区分开：本覆盖层**自下而上**
/// 推入并淡入，且不透明，收起时反向退出。队列覆盖层则是在它之上再推一层
/// （见 [openQueueOverlay]），层级顺序是 迷你条 → 播放页 → 队列。
Route<void> playbackPageRoute(PlaybackController controller) =>
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'playback'),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) =>
          PlaybackPage(controller: controller),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    );

/// 把队列覆盖层推在播放页之上；动效更快、更贴近「抽出一张面板」。
///
/// 播放页与队列都支持在无当前曲目时被打开：队列会显示「队列为空」，
/// 播放页会显示「暂无播放内容」。
Future<void> openQueueOverlay(
  BuildContext context,
  PlaybackController controller,
) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'queue'),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, animation, secondaryAnimation) =>
          QueueOverlayPage(controller: controller),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: animation, child: child),
          ),
    ),
  );
}

/// 全屏播放页：静止大封面、歌名与歌手、可拖动进度条、五键中控。
///
/// 刻意**没有**唱盘旋转、唱针与搓碟交互（`CONTEXT.md`「播放页」/ADR-0003），
/// 封面就是一张静止的方图。点封面与歌词**同层切换**（ADR-0007）：封面与歌词
/// 占据同一块区域，进度条与中控始终在下方。
///
/// 歌词在页面打开时随当前曲目**预取**（ADR-0007），切到歌词态不再发请求；
/// 歌词态的「屏幕常亮」开关离开歌词态或播放页即清除。
///
/// 页面打开时取一次当前曲目；没有当前曲目时显示空态而不是崩溃。
class PlaybackPage extends ConsumerStatefulWidget {
  const PlaybackPage({super.key, required this.controller});

  final PlaybackController controller;

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  /// 当前展示的是封面还是歌词（同层切换）。
  bool _showLyrics = false;

  /// 歌词态的屏幕常亮开关。
  bool _keepAwake = false;

  /// 在 `initState` 里取好实现：`dispose` 时不再碰 `ref`（此时容器可能已在拆除）。
  late final ScreenAwake _screenAwake;

  @override
  void initState() {
    super.initState();
    _screenAwake = ref.read(screenAwakeProvider);
  }

  @override
  void dispose() {
    // 离开播放页时清除常亮（ADR-0007）。
    if (_keepAwake) unawaited(_screenAwake.setEnabled(false));
    super.dispose();
  }

  void _setShowLyrics(bool show) {
    if (show == _showLyrics) return;
    setState(() {
      _showLyrics = show;
      // 离开歌词态即关掉常亮：这个开关只在歌词里有意义。
      if (!show) _keepAwake = false;
    });
    if (!show) unawaited(_screenAwake.setEnabled(false));
  }

  void _setKeepAwake(bool value) {
    setState(() => _keepAwake = value);
    unawaited(_screenAwake.setEnabled(value));
  }

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      body: SafeArea(
        child: PlaybackListenable(
          // 只关心「哪首、在不在播」：换歌才重建整页；进度条自己有边界。
          select: (controller) => controller.session.identity,
          builder: (context, controller) {
            final song = controller.session.currentSong;
            if (song == null) return const _EmptyPlayback();
            // 曲目身份用记录表示：队列重建产生的新对象不会让同一首重取歌词。
            final request = (
              songId: song.id,
              artist: song.artist ?? '',
              title: song.title,
            );
            // 打开播放页即订阅歌词——这就是**预取**（ADR-0007）：切到歌词态
            // 时数据已就位，不额外发请求。
            final lyrics = ref.watch(lyricsProvider(request));
            return Column(
              children: [
                _PlaybackTopBar(
                  controller: controller,
                  showKeepAwake: _showLyrics,
                  keepAwake: _keepAwake,
                  onToggleKeepAwake: () => _setKeepAwake(!_keepAwake),
                ),
                Expanded(
                  // 封面与歌词同层：淡入淡出切换，不是两层页面。
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showLyrics
                        ? LyricsView(
                            key: const ValueKey('lyrics'),
                            controller: controller,
                            songId: song.id,
                            lyrics: lyrics,
                            onTap: () => _setShowLyrics(false),
                            onRetry: () =>
                                ref.invalidate(lyricsProvider(request)),
                          )
                        : _CoverArea(
                            key: const ValueKey('cover'),
                            song: song,
                            onTap: () => _setShowLyrics(true),
                          ),
                  ),
                ),
                _ProgressBar(controller: controller),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: PlaybackControls(controller: controller),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 播放页的封面区：静止大封面，点一下切到歌词（ADR-0007）。
class _CoverArea extends StatelessWidget {
  const _CoverArea({super.key, required this.song, required this.onTap});

  final SubsonicSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 整块区域可点，不必精确点中封面图。
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AspectRatio(
            aspectRatio: 1,
            child: CoverArt(
              coverArtId: song.coverArtId,
              // 大图：让服务端按屏幕量级返回，不在客户端放大缩略图。
              size: 1024,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏：收起、歌名 + 歌手、歌词态的常亮开关、队列入口。
///
/// 与层级页面的标题栏同一口径：高度 [HoomyDimens.titleBarHeight]（50dp）、
/// 标题 [HoomyDimens.titleFontSize]（20sp，`CONTEXT.md`「标题栏」）。没有当前
/// 曲目时标题留空，顶栏结构不变 —— 收起按钮不会因为空态消失。
class _PlaybackTopBar extends StatelessWidget {
  const _PlaybackTopBar({
    required this.controller,
    required this.showKeepAwake,
    required this.keepAwake,
    required this.onToggleKeepAwake,
  });

  final PlaybackController controller;

  /// 是否处于歌词态：常亮开关只在歌词态出现。
  final bool showKeepAwake;

  /// 常亮当前是否开启。
  final bool keepAwake;

  final VoidCallback onToggleKeepAwake;

  @override
  Widget build(BuildContext context) {
    final song = controller.session.currentSong;
    return Row(
      children: [
        Expanded(
          child: _PlaybackTitleBar(
            title: song?.title ?? '',
            subtitle: songArtistText(song),
            onClose: () => Navigator.of(context).maybePop(),
          ),
        ),
        // 收藏当前曲目：没有当前曲目时（空态）不出现。
        if (song != null)
          StarButton(
            target: songStar(song.id),
            starred: song.isStarred,
          ),
        if (showKeepAwake)
          IconButton(
            icon: Icon(keepAwake ? Icons.lightbulb : Icons.lightbulb_outline),
            tooltip: keepAwake ? '关闭屏幕常亮' : '屏幕常亮',
            onPressed: onToggleKeepAwake,
          ),
        PlaybackListenable(
          select: (controller) => controller.session.queue.queue.length,
          builder: (context, controller) => IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: '播放队列',
            onPressed: () => openQueueOverlay(context, controller),
          ),
        ),
      ],
    );
  }
}

/// 可拖动的进度条：当前时间 / 剩余时间，拖动松手即跳转。
///
/// 进度来自引擎的 [PlaybackController.session.position]，每 ~200ms 一跳；
/// 本部件是唯一跟着进度重建的边界，因此整页与中控按钮不陪着重绘。
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.controller});

  final PlaybackController controller;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  /// 拖动中的位置；null 表示没在拖，显示引擎的真实进度。
  Duration? _dragging;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final session = widget.controller.session;
        final duration = session.duration;
        // 进度条的刻度取**秒**：调用处（含测试）读起来就是秒数，不必再换算。
        final total = duration?.inSeconds ?? 0;
        final current = _dragging ?? session.position;
        final value = total <= 0
            ? 0.0
            : (current.inMilliseconds / 1000).clamp(0, total).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  // 轨道细线、滑块小圆点；不用默认的胶囊形叠加层。
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: palette.playing,
                  inactiveTrackColor: palette.divider,
                  thumbColor: palette.playing,
                ),
                child: Slider(
                  // 时长未知时禁用拖动，避免跳到一个没有意义的比例。
                  value: value,
                  max: total <= 0 ? 1 : total.toDouble(),
                  onChanged: total <= 0
                      ? null
                      : (seconds) => setState(
                          () => _dragging = _secondsToPosition(seconds, total),
                        ),
                  onChangeEnd: total <= 0
                      ? null
                      : (seconds) {
                          final target = _secondsToPosition(seconds, total);
                          setState(() => _dragging = null);
                          unawaited(widget.controller.seek(target));
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatPlaybackDuration(current)!, style: _timeStyle(palette)),
                    Text(
                      _remainingText(duration, current),
                      style: _timeStyle(palette),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 右侧文字：剩余时间写成 `-m:ss`（走到头就是 `0:00`）。
  ///
  /// 拖动可以越过曲目末尾，此时剩余为负，改写成 `+m:ss` 的超出量，不出现
  /// `--0:05` 这种双符号。时长未知时退回 `0:00` —— 没有总长就算不出剩余。
  String _remainingText(Duration? duration, Duration current) {
    if (duration == null) return '0:00';
    final remaining = duration - current;
    return formatPlaybackDuration(
      remaining.isNegative ? -remaining : remaining,
      prefix: remaining.isNegative ? '+' : '-',
    )!;
  }

  /// 把进度条刻度上的秒数收敛成合法的跳转目标（允许小数秒）。
  Duration _secondsToPosition(double seconds, int total) => Duration(
    milliseconds: (seconds * 1000).round().clamp(0, total * 1000),
  );

  TextStyle _timeStyle(HoomyPalette palette) => TextStyle(
    fontSize: HoomyDimens.listSubtitleFontSize,
    color: palette.textSecondary,
  );
}

/// 没有当前曲目时的空态：不留一个半截页面，也不给点不动的控制。
class _EmptyPlayback extends StatelessWidget {
  const _EmptyPlayback();

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    // 与播放态的顶栏同高同字号（50dp / 20sp）：只是标题换成空态文案、
    // 没有队列入口，收起按钮的位置不变。
    return Column(
      children: [
        _PlaybackTitleBar(
          title: '暂无播放内容',
          onClose: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Center(
            child: Text(
              '队列里还没有歌',
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

/// 播放页顶栏里与「层级页面标题栏」对齐的那一半：收起按钮 + 20sp 标题。
///
/// 播放态与空态共用，避免两处各写一遍 50dp/20sp 后各自演化。
class _PlaybackTitleBar extends StatelessWidget {
  const _PlaybackTitleBar({
    required this.title,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return SizedBox(
      height: HoomyDimens.titleBarHeight,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: '收起播放页',
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HoomyDimens.titleFontSize,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HoomyDimens.listSubtitleFontSize,
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

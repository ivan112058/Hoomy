import 'package:flutter/material.dart';

import '../../core/platform/form_factor.dart';
import '../../core/theme/hoomy_theme.dart';
import '../../data/subsonic/models.dart';
import '../../player/playback_controller.dart';
import '../shared/hoomy_icon_button.dart';
import '../shared/hoomy_list_row.dart';
import '../shared/song_secondary_text.dart';
import 'playback_listenable.dart';

/// 队列覆盖层：查看与调整当前播放队列。
///
/// 按队列下标切成连续的三段（`PlaybackQueueState` 的分区）：
/// **已播放**（当前之前）、**正在播放**（当前那首，有明确标识）、
/// **即将播放**（当前之后）。后两段与队列自然序一致，因此界面里的位置
/// 就是队列下标：
///
/// - 点任意一首即跳到它（[PlaybackController.playAt]）；
/// - 「即将播放」段可调序：手机形态拖拽手柄，TV 形态「聚焦行 + 左右键」
///   （ADR-0013 决策 4），两条路径都落到
///   [PlaybackController.reorderUpcoming]，重排规则只有一份；
/// - 顶栏一键清空「即将播放」（[PlaybackController.clearUpcoming]）。
///
/// 以全屏覆盖层形式压在整个应用之上（含播放页）：层级比页面路由更明确，
/// 动效由调用方（`PlaybackPage` 的队列按钮）决定。
///
/// 随机模式下队列仍按这份顺序显示与编辑；随机只改变前进的次序，不改变
/// 「接下来有哪些歌、拖成什么顺序」这份用户意图（票据 09 的实现决策）。
class QueueOverlayPage extends StatelessWidget {
  const QueueOverlayPage({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: AppBar(
        leading: HoomyIconButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: '收起队列',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        automaticallyImplyLeading: false,
        title: const Text('播放队列'),
        actions: [
          PlaybackListenable(
            select: (controller) => controller.session.queue,
            builder: (context, controller) => HoomyIconButton(
              icon: Icons.clear_all,
              tooltip: '清空即将播放',
              onPressed: controller.hasUpcoming ? controller.clearUpcoming : null,
            ),
          ),
        ],
      ),
      body: PlaybackListenable(
        // 队列内容、当前曲目与模式变化才重建；进度不带着整份列表重绘。
        select: (controller) => controller.session.queue,
        builder: (context, controller) => _QueueBody(controller: controller),
      ),
    );
  }
}

/// 队列的三段列表。
///
/// 分区取自 [PlaybackController.view]（**本次播放顺序**的三段切片），不是
/// 「队列自然序 + 当前下标」：随机模式下两者不同，用后者会把真正下一首
/// 标成已播放。段内元素是播放顺序里的位置，点选与重排都按它传回控制器。
class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final songs = controller.session.queue.queue;
    if (songs.isEmpty) {
      return Center(
        child: Text(
          '队列为空',
          style: TextStyle(color: HoomyPalette.of(context).textSecondary),
        ),
      );
    }

    final isTv = HoomyFormFactorScope.isTv(context);
    final view = controller.view;
    final played = view.played;
    final upcoming = view.upcoming;

    return CustomScrollView(
      slivers: [
        if (played.isNotEmpty) ...[
          const _SectionHeader('已播放'),
          SliverList.builder(
            itemCount: played.length,
            // 最近的排在最上面：已播放段整体倒序。
            itemBuilder: (context, i) {
              // 行序是倒序，但「跳转位置」要用正序下标。
              final position = played.length - 1 - i;
              return _QueueRow(
                song: played[position],
                onTap: () => controller.playAt(position),
              );
            },
          ),
        ],
        if (view.currentSong != null) ...[
          const _SectionHeader('正在播放'),
          SliverToBoxAdapter(
            child: _QueueRow(
              song: view.currentSong!,
              current: true,
              // 当前曲目在播放顺序里的位置就是已播放段的长度。
              onTap: () => controller.playAt(view.played.length),
            ),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          _SectionHeader(
            '即将播放',
            // 可发现性：左右键重排没有可见的抓手，靠这一句说明（ADR-0013 决策 4）。
            hint: isTv ? '左右键调整顺序 · 确认键跳播' : null,
          ),
          if (isTv)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _QueueRow(
                  // 行 key 跟着曲目走，配合下面 `findChildIndexCallback`：重排后
                  // 元素（连同焦点）跟着歌一起移动，焦点不会因为列表重建而掉到
                  // 别处。
                  key: ValueKey(_rowKey(upcoming[i])),
                  song: upcoming[i],
                  onTap: () => controller.playAt(upcomingOffset + i),
                  onMovePrevious: () => _moveTo(upcoming, i, i - 1),
                  onMoveNext: () => _moveTo(upcoming, i, i + 1),
                ),
                childCount: upcoming.length,
                // 按 key 找新下标：曲目被上下移动后，sliver 复用同一个元素，
                // 停在行上的焦点因此保持不动。
                findChildIndexCallback: (key) {
                  final id = (key as ValueKey<String>).value;
                  final index = upcoming.indexWhere(
                    (song) => _rowKey(song) == id,
                  );
                  return index < 0 ? null : index;
                },
              ),
            )
          else
            SliverReorderableList(
              itemCount: upcoming.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _moveTo(upcoming, oldIndex, newIndex),
              itemBuilder: (context, i) {
                final song = upcoming[i];
                return _QueueRow(
                  key: ValueKey(_rowKey(song)),
                  song: song,
                  onTap: () => controller.playAt(upcomingOffset + i),
                  // 拖拽只从行尾的手柄发起，不抢整行的点击。手柄只保留在手机
                  // 形态：TV 上是「聚焦行 + 左右键」那条路径。
                  dragHandle: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                );
              },
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// 「即将播放」在播放顺序里的起始位置：已播放段 + 当前曲目。
  int get upcomingOffset => controller.view.played.length + 1;

  /// 行 key：跟着曲目走，重排时元素与焦点一起移动。
  String _rowKey(SubsonicSong song) => 'queue-${song.id}';

  /// 把「即将播放」段内的曲目从 [from] 挪到 [to]，落成新的整段顺序。
  ///
  /// 两条路径共用它：TV 的左右键（±1 格）与手机的拖拽
  /// （`onReorderItem` 已把落点调成移除旧项后的下标）。越界不动（不是错误）：
  /// 焦点停在行上、列表不重排。
  void _moveTo(List<SubsonicSong> upcoming, int from, int to) {
    if (to < 0 || to >= upcoming.length || from == to) return;
    final order = [...upcoming];
    final moved = order.removeAt(from);
    order.insert(to, moved);
    controller.reorderUpcoming(order);
  }
}

/// 分区标题：小字、次文字色，整宽无缩进；可选的行尾提示。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.hint});

  final String title;

  /// 行尾提示（TV 上的重排说明）；为空则不占位。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    final hint = this.hint;
    return SliverToBoxAdapter(
      child: Container(
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: palette.surfaceRaised,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  color: palette.textSecondary,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint,
                style: TextStyle(
                  fontSize: HoomyDimens.listSubtitleFontSize,
                  color: palette.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 队列里的一行：歌曲行 + 可选的拖拽手柄，当前曲目带明确播放标识。
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.song,
    this.current = false,
    this.onTap,
    this.dragHandle,
    this.onMovePrevious,
    this.onMoveNext,
  });

  final SubsonicSong song;

  /// 是否是正在播放的那一首：行首出现播放标识。
  final bool current;

  final VoidCallback? onTap;

  /// 行尾的拖拽手柄；不需要排序的分区或 TV 形态传 null。
  final Widget? dragHandle;

  /// 左键 = 上移（TV 重排）。
  final VoidCallback? onMovePrevious;

  /// 右键 = 下移（TV 重排）。
  final VoidCallback? onMoveNext;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Material(
      // 拖拽代理需要在没有祖先 Material 的 Overlay 里也能上色。
      color: current ? palette.surfaceRaised : palette.card,
      child: Column(
        children: [
          HoomyListRow(
            title: song.title,
            subtitle: songSecondaryText(song),
            highlighted: current,
            onTap: onTap,
            onMovePrevious: onMovePrevious,
            onMoveNext: onMoveNext,
            // 只有正在播放的那一行显示标识，其余留出等宽占位让文字对齐；
            // 颜色跟着整行的高亮反馈走（高亮时变白），不绕开 [HoomyListRow]。
            leadingBuilder: (state) => Icon(
              Icons.play_arrow,
              size: 18,
              color: current
                  ? (state.active ? state.foreground : palette.playing)
                  : const Color(0x00000000),
            ),
            trailing: dragHandle == null ? null : (_) => dragHandle!,
          ),
          const HoomyRowDivider(),
        ],
      ),
    );
  }
}

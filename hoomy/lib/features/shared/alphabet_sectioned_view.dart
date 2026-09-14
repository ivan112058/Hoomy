import 'package:flutter/material.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';
import 'alphabet_index_bar.dart';

/// 分组头高度。
const kSectionHeaderExtent = 28.0;

/// 低于这个条目数就不显示快捷栏：一屏能看完时它只占位、不提供便利。
const kAlphabetIndexBarMinItems = 20;

/// 分组头：不透明底色，列表内容滚到它下面（例如快速跳转后回滚）时不会透出。
///
/// 字母分组的组头与详情页的段落标题（歌手详情的「专辑」「全部歌曲」）
/// 共用这一个实现。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Container(
      height: kSectionHeaderExtent,
      width: double.infinity,
      color: palette.surfaceRaised,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: HoomyDimens.listSubtitleFontSize,
          fontWeight: FontWeight.bold,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// 字母分组滚动视图：分组头 + 右缘 A–Z 快捷栏。
///
/// 组头**不吸顶**：Flutter 的 pinned `SliverPersistentHeader` 不会把前一个
/// 组头推出去，而是让它们全部堆在视口顶部，滚到靠后的分组时顶部会叠出一摞
/// 字母挡住内容。要做「当前分组吸顶」得自己实现推出效果，本票据没要求，
/// 因此组头只随内容滚动。
///
/// [AlphabetSectionedList] 与 [AlphabetSectionedGrid] 的实现基座，不对页面
/// 公开：它把「调用方必须复刻布局算式」当契约，暴露出去容易算错高度。
///
/// 快捷栏跳转要跳到**尚未构建**的分组（列表是懒加载的，拿不到它的
/// RenderObject），所以偏移只能自己算：每组占「组头 + [contentExtentOf]」，
/// 逐组累加即得。因此 [contentExtentOf] 必须与该组 sliver 的实际高度一致。
class _AlphabetSectionedScrollView<T> extends StatefulWidget {
  const _AlphabetSectionedScrollView({
    required this.sections,
    required this.contentExtentOf,
    required this.sectionBuilder,
  });

  /// 非空分组，已按 A–Z、`#` 排好序。
  final List<AlphabetSection<T>> sections;

  /// 一组内容（不含组头）在滚动方向上的总高度。
  final double Function(AlphabetSection<T> section) contentExtentOf;

  /// 把一组内容构建成 sliver（组头由本组件统一绘制）。
  final Widget Function(BuildContext context, AlphabetSection<T> section)
      sectionBuilder;

  @override
  State<_AlphabetSectionedScrollView<T>> createState() =>
      _AlphabetSectionedScrollViewState<T>();
}

class _AlphabetSectionedScrollViewState<T>
    extends State<_AlphabetSectionedScrollView<T>> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 每个组头的滚动偏移，顺序与 [_AlphabetSectionedScrollView.sections] 一致。
  List<double> _sectionOffsets() {
    final offsets = <double>[];
    var offset = 0.0;
    for (final section in widget.sections) {
      offsets.add(offset);
      offset += kSectionHeaderExtent + widget.contentExtentOf(section);
    }
    return offsets;
  }

  void _jumpToKey(String key) {
    final index = widget.sections.indexWhere((section) => section.key == key);
    if (index < 0 || !_controller.hasClients) return;
    // 末尾的分组可能顶不满一屏，jumpTo 会自行夹到 maxScrollExtent。
    _controller.jumpTo(_sectionOffsets()[index]);
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final total = sections.fold<int>(0, (sum, s) => sum + s.length);
    final showIndexBar = total >= kAlphabetIndexBarMinItems;

    return Stack(
      children: [
        CustomScrollView(
          controller: _controller,
          slivers: [
            for (final section in sections) ...[
              SliverToBoxAdapter(
                child: SectionHeader(title: section.key),
              ),
              widget.sectionBuilder(context, section),
            ],
          ],
        ),
        if (showIndexBar)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Center(
              child: AlphabetIndexBar(
                availableKeys: sections.map((s) => s.key).toSet(),
                onSelected: _jumpToKey,
              ),
            ),
          ),
      ],
    );
  }
}

/// 行式分组列表：固定行高的条目纵向排列，用于歌曲与歌手。
class AlphabetSectionedList<T> extends StatelessWidget {
  const AlphabetSectionedList({
    super.key,
    required this.sections,
    required this.itemExtent,
    required this.itemBuilder,
  });

  final List<AlphabetSection<T>> sections;

  /// 单个条目占位高度，需包含条目自带的分隔线。
  final double itemExtent;

  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return _AlphabetSectionedScrollView<T>(
      sections: sections,
      contentExtentOf: (section) => section.length * itemExtent,
      sectionBuilder: (context, section) => SliverFixedExtentList(
        itemExtent: itemExtent,
        delegate: SliverChildBuilderDelegate(
          (context, i) => itemBuilder(context, section.items[i], i),
          childCount: section.length,
        ),
      ),
    );
  }
}

/// 网格式分组列表：固定列数、固定单元高度，用于专辑。
class AlphabetSectionedGrid<T> extends StatelessWidget {
  const AlphabetSectionedGrid({
    super.key,
    required this.sections,
    required this.columns,
    required this.cellExtent,
    required this.itemBuilder,
    required this.spacing,
  });

  final List<AlphabetSection<T>> sections;

  /// 固定列数，不随屏宽改变（`CONTEXT.md`「专辑网格」）。
  final int columns;

  /// 单个网格单元的高度（封面 + 文字）。
  final double cellExtent;

  /// 行距、列距与左右内边距，统一一个值。
  final double spacing;

  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  static int _rows(int count, int columns) => (count + columns - 1) ~/ columns;

  @override
  Widget build(BuildContext context) {
    // 每组底部补一个行距，使每组占位恰为 rows * (cellExtent + spacing)，
    // 与 SliverGrid 内部只在行间留 spacing 的画法配平。
    double groupExtent(AlphabetSection<T> section) =>
        _rows(section.length, columns) * (cellExtent + spacing);

    return _AlphabetSectionedScrollView<T>(
      sections: sections,
      contentExtentOf: groupExtent,
      sectionBuilder: (context, section) => SliverPadding(
        padding: EdgeInsets.only(
          left: spacing,
          right: spacing,
          bottom: spacing,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: cellExtent,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => itemBuilder(context, section.items[i], i),
            childCount: section.length,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/alphabet/alphabet.dart';
import '../../core/theme/hoomy_theme.dart';

/// 快捷栏宽度：只覆盖列表右缘一条窄带，不挤压列表布局。
const kAlphabetIndexBarWidth = 24.0;

/// 单个字母的高度；27 个键在常见屏高内能完整竖排。
const _letterExtent = 14.0;

/// A–Z 快捷栏：贴在列表右缘，按下即跳到对应分组。
///
/// 始终竖排完整的 A–Z 与 `#`，布局不随曲库内容跳动；当前数据里不存在的
/// 组淡显且不可点。是否显示由调用方按曲库规模决定（见
/// `alphabet_sectioned_view.dart` 的条目数阈值）。
class AlphabetIndexBar extends StatelessWidget {
  const AlphabetIndexBar({
    super.key,
    required this.availableKeys,
    required this.onSelected,
  });

  /// 当前数据里真实存在的组键。
  final Set<String> availableKeys;

  /// 点中某个可用组键时回调。
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = HoomyPalette.of(context);
    return Container(
      width: kAlphabetIndexBarWidth,
      // 半透明页面底色：列表滚到字母下方时仍读得清，又不像一整条色带。
      color: palette.pageBackground.withValues(alpha: 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in alphabetKeys)
            _IndexLetter(
              key: ValueKey('alphabet-index-$key'),
              letter: key,
              available: availableKeys.contains(key),
              onTap: () => onSelected(key),
              color: palette.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _IndexLetter extends StatelessWidget {
  const _IndexLetter({
    super.key,
    required this.letter,
    required this.available,
    required this.onTap,
    required this.color,
  });

  final String letter;
  final bool available;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 不存在的组点了也不跳，避免跳到一个空段。
      onTap: available ? onTap : null,
      child: SizedBox(
        width: kAlphabetIndexBarWidth,
        height: _letterExtent,
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 10,
              color: available ? color : color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

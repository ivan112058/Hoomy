import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import 'hoomy_list_row.dart';

/// 「N 首」：列表行的行尾与详情页的头部共用同一份文案与字号。
///
/// 服务端没给条数时**不占位**，而不是编成「0 首」—— 曲目数是服务端解析
/// 出来的事实，缺了就缺了。
class SongCountText extends StatelessWidget {
  const SongCountText({super.key, required this.count, this.state});

  final int? count;

  /// 所在行的按压状态：在列表行里传它，颜色跟随整行反馈；
  /// 详情页头部之类的非行内场景不传，用次文字色。
  final HoomyRowState? state;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    if (count == null) return const SizedBox.shrink();
    return Text(
      '$count 首',
      style: TextStyle(
        fontSize: HoomyDimens.listSubtitleFontSize,
        color: state?.foreground ?? HoomyPalette.of(context).textSecondary,
      ),
    );
  }
}

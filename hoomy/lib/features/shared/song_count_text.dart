import 'package:flutter/material.dart';

import '../../core/theme/hoomy_theme.dart';
import 'hoomy_list_row.dart';

/// 行尾的「N 首」：跟随所在行的按压反馈着色。
///
/// 服务端没给条数时**不占位**，而不是编成「0 首」—— 曲目数是服务端解析
/// 出来的事实，缺了就缺了。
class SongCountText extends StatelessWidget {
  const SongCountText({super.key, required this.count, required this.state});

  final int? count;
  final HoomyRowState state;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    if (count == null) return const SizedBox.shrink();
    return Text(
      '$count 首',
      style: TextStyle(
        fontSize: HoomyDimens.listSubtitleFontSize,
        color: state.foreground,
      ),
    );
  }
}

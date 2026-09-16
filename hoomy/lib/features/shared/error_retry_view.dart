import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../../data/subsonic/subsonic_client.dart';
import 'hoomy_button.dart';

/// 取数失败：给出可读原因与「重试」，不留下空白页。
///
/// 列表页的 `AsyncView` 与播放页的歌词都用这一份，避免两处各写一套
/// 「文案 + 重试按钮」的形状。「重试」用 [HoomyButton] 的描边态：
/// 视觉与原来的 `OutlinedButton` 一致，TV 上聚焦时整块铺交互蓝、文字变白。
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// 展示给用户的失败原因。
  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            HoomyButton(
              bordered: true,
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// `SubsonicException` 已由协议层映射成可读文案，优先取它；
/// 其它异常退化为 `toString()`，只在开发期遇到，用于定位。
///
/// Riverpod 会把 provider 抛出/失败的异常包一层 [ProviderException]，
/// 这里拆掉包装，否则用户看到的是一整段栈信息。
String describeError(Object error) {
  if (error is ProviderException) return describeError(error.exception);
  return error is SubsonicException ? error.message : '$error';
}

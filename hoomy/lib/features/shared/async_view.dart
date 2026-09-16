import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/form_factor.dart';
import 'error_retry_view.dart';
import 'hoomy_icon_button.dart';

/// 把一个**异步值**画成载入／错误重试／空态／内容。
///
/// 页面只订阅调用方给的异步值，重试也只是让那个值重取一次 —— 取数身份与失效
/// 不落在页面里（ADR-0015 决策 4）。这是列表页三态呈现的**唯一**一份。
class AsyncValueView<T> extends ConsumerWidget {
  const AsyncValueView({
    super.key,
    required this.provider,
    required this.itemBuilder,
    this.emptyMessage = '这里还没有内容',
    this.isEmpty,
  });

  /// 要订阅的取数。传 provider（而不是裸异步值）是为了让「重试」也有归宿：
  /// 失效发生在模块边界上，页面只说它要什么数据。
  final FutureProvider<T> provider;

  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyMessage;

  /// 数据非 `Iterable` 时的空态判据（如「播放列表没有曲目」）。
  /// 默认只按 `Iterable.isEmpty` 判断。
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(provider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetryView(
        message: describeError(error),
        onRetry: () => ref.invalidate(provider),
      ),
      data: (data) {
        if (_isEmpty(data)) {
          return Center(child: Text(emptyMessage));
        }
        return itemBuilder(context, data);
      },
    );
  }

  bool _isEmpty(T data) {
    if (isEmpty case final predicate?) return predicate(data);
    return data is Iterable && data.isEmpty;
  }
}

/// 页面级脚手架：统一 AppBar。
///
/// 层级返回交给 AppBar 的默认行为：作为 Tab 根页时路由不可弹出，不显示返回键；
/// 被 push 成详情页时自动出现返回键。显式传入 [leading]（如「更多」页的设置图标）
/// 则用传入的那个。
///
/// TV 上返回键改用 [HoomyIconButton]：AppBar 自动插入的返回键是个普通
/// `IconButton`，聚焦反馈是 Material 默认的浅色叠加，在 10-foot 距离下看不清；
/// 硬件返回键本来就由系统交给 Navigator（不依赖这个按钮），这里只是给一个
/// 看得清的可聚焦入口。
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.leading, this.actions, required this.body});

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final isTv = HoomyFormFactorScope.isTv(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: leading ??
            (isTv && canPop
                ? HoomyIconButton(
                    icon: Icons.arrow_back,
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null),
        automaticallyImplyLeading: !isTv,
        actions: actions,
      ),
      body: body,
    );
  }
}

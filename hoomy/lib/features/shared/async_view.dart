import 'package:flutter/material.dart';

import 'error_retry_view.dart';

/// 列表页通用的异步骨架：加载中 / 错误重试 / 空态。
///
/// [load] 只在首次构建与用户点「重试」时调用，不会因为父组件 rebuild 而重新取数。
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.emptyMessage = '这里还没有内容',
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyMessage;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _retry() {
    final future = widget.load();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorRetryView(
            message: describeError(snapshot.error!),
            onRetry: _retry,
          );
        }
        final data = snapshot.data;
        if (data == null || (data is Iterable && data.isEmpty)) {
          return Center(child: Text(widget.emptyMessage));
        }
        return widget.itemBuilder(context, data as T);
      },
    );
  }
}

/// 页面级脚手架：统一 AppBar。
///
/// 层级返回交给 AppBar 的默认行为：作为 Tab 根页时路由不可弹出，不显示返回键；
/// 被 push 成详情页时自动出现返回键。显式传入 [leading]（如「更多」页的设置图标）
/// 则用传入的那个。
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.leading, this.actions, required this.body});

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: leading,
        actions: actions,
      ),
      body: body,
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/subsonic/subsonic_client.dart';

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
          return _ErrorView(error: snapshot.error!, onRetry: _retry);
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

/// 取数失败：给出可读原因与「重试」，不留下空白页。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_describe(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// `SubsonicException` 已由协议层映射成可读文案，优先取它；
/// 其它异常退化为 `toString()`，只在开发期遇到，用于定位。
String _describe(Object error) =>
    error is SubsonicException ? error.message : '$error';

/// 页面级脚手架：统一 AppBar。
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
        automaticallyImplyLeading: leading != null,
      ),
      body: body,
    );
  }
}

import 'package:flutter/material.dart';

/// 列表页通用的异步骨架：加载中 / 错误重试 / 空态。
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.itemBuilder,
    this.emptyMessage = '这里还没有内容',
  });

  final Future<T> future;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(message: snapshot.error.toString());
        }
        final data = snapshot.data;
        if (data == null) {
          return Center(child: Text(emptyMessage));
        }
        return itemBuilder(context, data);
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

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

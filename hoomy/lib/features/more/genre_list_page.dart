import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../shared/async_view.dart';

/// 风格列表：服务端解析出的曲库流派分组。
class GenreListPage extends ConsumerWidget {
  const GenreListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genreRepositoryProvider);
    if (genres == null) return const SizedBox.shrink();
    return PageScaffold(
      title: '风格',
      body: AsyncView(
        load: genres.getGenres,
        emptyMessage: '曲库里还没有风格信息',
        itemBuilder: (context, list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 0.67, indent: 16),
          itemBuilder: (context, i) {
            final genre = list[i];
            return ListTile(
              title: Text(genre.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text('${genre.songCount ?? 0} 首'),
            );
          },
        ),
      ),
    );
  }
}

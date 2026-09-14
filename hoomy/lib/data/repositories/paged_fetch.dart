/// 各 repository 共用的分页取全量循环。
///
/// 分页只是传输手段，不是 UI 概念：Subsonic 的列表响应不带总数，
/// 只能靠 offset 翻页直到短页或空页（ADR-0005）。
library;

/// 列表取数的单页条数。会话内部的取数共用这一个值，不再各自声明副本。
///
/// `search3` 对条数没有硬上限；`getAlbumList2` 与 `getSongsByGenre` 的上限是
/// 服务端定死的 500。500 是实测曲库（908 首）下两次请求取全量的取值（ADR-0005）。
const kListPageSize = 500;

/// 从 `offset = 0` 起按 [kListPageSize] 递增调用 [fetchPage]，直到出现短页或空页。
///
/// 结果按 [idOf] 去重并保留首次出现的顺序。服务端若返回重叠页，
/// 重复项被丢弃；若不按 offset 翻页（整页都是重复项），立即终止，避免死循环。
/// 因此返回值不含重复项，也不会无限翻页。
Future<List<T>> fetchAllPages<T>({
  required Future<List<T>> Function(int offset) fetchPage,
  required String Function(T item) idOf,
}) async {
  final items = <T>[];
  final seenIds = <String>{};
  var offset = 0;

  while (true) {
    final page = await fetchPage(offset);
    var added = 0;
    for (final item in page) {
      if (seenIds.add(idOf(item))) {
        items.add(item);
        added++;
      }
    }
    // 空页或短页：已经到达末尾。
    if (page.length < kListPageSize) break;
    // 防御：整页都是重复项说明服务端没有按 offset 翻页，继续下去会死循环。
    if (added == 0) break;
    offset += kListPageSize;
  }

  return items;
}

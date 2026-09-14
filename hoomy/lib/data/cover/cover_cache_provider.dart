import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'cover_cache.dart';

/// 封面磁盘缓存。
///
/// 生产在 `main()` 里构造好并 override（缓存目录要异步解析，且它不依赖登录态
/// —— 认证参数在下载地址里）。默认 null 表示没有缓存能力，界面直接请求服务端；
/// widget 测试因此无需触碰文件系统。
final coverCacheProvider = Provider<CoverCache?>((ref) => null);

/// 封面缓存当前占用的字节数（供设置页显示，票据 15）。
///
/// 缓存能力缺失（未拿到可写目录）时为 null —— 与「占用为 0」是两回事：
/// 前者没有磁盘缓存可清，后者有缓存但里面是空的。清除缓存后由设置页
/// `invalidate` 本 provider 重新查询。
final coverCacheBytesProvider = FutureProvider<int?>((ref) async {
  final cache = ref.watch(coverCacheProvider);
  if (cache == null) return null;
  return cache.totalBytes();
});

/// 打开生产封面缓存；目录不可用时返回 null（界面降级为直连请求）。
///
/// [dio] 是应用唯一的 HTTP 传输（ADR-0015 决策 5）：封面下载与登录、曲库
/// 共用同一条，因此传输策略只有一处。
Future<CoverCache?> openCoverCache({required Dio dio}) async {
  try {
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/cover_art');
    await directory.create(recursive: true);
    return CoverCache(
      directory: directory,
      fetch: _dioFetcher(dio),
    );
  } catch (_) {
    // 拿不到可写目录：没有磁盘缓存也能用，不要把启动拦下。
    return null;
  }
}

/// 用 Dio 下载封面字节。认证走 URL 查询串（ADR-0010），因此不需要额外请求头。
CoverFetcher _dioFetcher(Dio dio) => (uri) async {
  final response = await dio.get<List<int>>(
    uri.toString(),
    options: Options(responseType: ResponseType.bytes),
  );
  final data = response.data;
  return data == null ? Uint8List(0) : Uint8List.fromList(data);
};

import 'dart:io';
import 'dart:typed_data';

/// 封面下载器：给一个地址，返回图片字节。
///
/// 缓存不关心认证怎么拼、用哪个 HTTP 栈 —— 地址由调用方按 `coverArt` id 生成
/// （`SubsonicClient.coverArtUri`），缓存只管落盘。
typedef CoverFetcher = Future<Uint8List> Function(Uri uri);

/// 封面磁盘缓存：按 `coverArt` id 落盘，不设过期，失效只靠清除（ADR-0006）。
///
/// 缓存逻辑集中在这一处：界面拿到的只是文件，不直接读写目录。
///
/// **失败降级**：读写或下载的任何一环失败都不抛异常，而是返回 null ——
/// 调用方（`CoverArt`）据此直接请求服务端，界面不会因为缓存坏掉而崩。
class CoverCache {
  CoverCache({required this.directory, required this.fetch});

  /// 缓存目录。测试注入临时目录；生产是应用支持目录下的 `cover_art`。
  final Directory directory;

  final CoverFetcher fetch;

  /// 同一张封面的并发请求合并成一次下载，避免同图重复请求。
  final Map<String, Future<File?>> _inFlight = {};

  /// 取封面文件：命中缓存直接返回；未命中先下载再返回。
  ///
  /// [coverArtId] 决定缓存身份；[size] 参与文件名（同一张图的不同尺寸各存一份）；
  /// [uri] 是下载地址（含认证查询串）。任何失败返回 null，调用方降级为直连。
  Future<File?> file(String coverArtId, {int? size, required Uri uri}) {
    final name = _fileName(coverArtId, size);
    return _inFlight.putIfAbsent(name, () {
      final load = _load(name, uri);
      // 回调体必须用块语句丢弃 `remove` 的返回值：`whenComplete` 会把回调返回的
      // Future 一并等待，而 `remove` 返回的正是留在表里的这个 future，会自我等待
      // 到死锁（进程随即因事件循环空转而退出）。
      return load.whenComplete(() {
        _inFlight.remove(name);
      });
    });
  }

  /// 缓存当前占用的字节数；目录不存在或不可读时按 0 计。
  Future<int> totalBytes() async {
    try {
      if (!await directory.exists()) return 0;
      var total = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 清空整个缓存；清除后再访问会重新下载。失败不抛异常。
  Future<void> clear() async {
    try {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 单个文件删不掉不影响其余文件：整体清除尽力而为。
        }
      }
    } catch (_) {
      // 目录不可读时无从清除，按「已清除」处理。
    }
  }

  Future<File?> _load(String name, Uri uri) async {
    try {
      final target = File('${directory.path}/$name');
      if (await target.exists()) {
        if (await target.length() > 0) return target;
        // 上次写到一半留下的空文件：视为未命中，删掉重下。
        await target.delete();
      }

      final bytes = await fetch(uri);
      if (bytes.isEmpty) return null;

      await directory.create(recursive: true);
      // 先写临时文件再改名：下载中断不会留下半张图被当成命中。
      final tmp = File('${directory.path}/$name.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// 缓存文件名：id 做 URI 编码以免出现路径分隔符；尺寸不同则各存一份。
  String _fileName(String coverArtId, int? size) {
    final encoded = Uri.encodeComponent(coverArtId);
    return size == null ? '$encoded.img' : '$encoded.s$size.img';
  }
}

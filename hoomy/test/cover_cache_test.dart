import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/cover/cover_cache.dart';

/// 票据 07：封面磁盘缓存（ADR-0006）。
///
/// 验收面：按 `coverArt` id 落盘、命中不再请求、占用可查询、可整体清除、
/// 清除后重新下载、读写失败不崩（返回 null 让界面降级直连）。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hoomy_cover_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final uri = Uri.parse(
    'http://nas.local:4533/rest/getCoverArt.view?id=c1&u=alice',
  );
  final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

  /// 记录下载次数的缓存。
  ({CoverCache cache, List<Uri> requests}) counting() {
    final requests = <Uri>[];
    final cache = CoverCache(
      directory: dir,
      fetch: (u) async {
        requests.add(u);
        return bytes;
      },
    );
    return (cache: cache, requests: requests);
  }

  test('首次访问下载并落盘，再次访问命中缓存不再请求', () async {
    final (:cache, :requests) = counting();

    final first = await cache.file('c1', uri: uri);
    expect(first, isNotNull);
    expect(await first!.exists(), isTrue);
    expect(await first.readAsBytes(), bytes);
    expect(requests, hasLength(1));

    final second = await cache.file('c1', uri: uri);
    expect(second!.path, first.path);
    expect(requests, hasLength(1), reason: '命中缓存时不应再发起请求');
  });

  test('新的缓存实例指向同一目录仍命中：确实是磁盘缓存而非内存缓存', () async {
    final requests = <Uri>[];
    Future<Uint8List> fetch(Uri u) async {
      requests.add(u);
      return bytes;
    }

    await CoverCache(directory: dir, fetch: fetch).file('c1', uri: uri);
    final second = await CoverCache(
      directory: dir,
      fetch: fetch,
    ).file('c1', uri: uri);

    expect(second, isNotNull);
    expect(requests, hasLength(1));
  });

  test('不同 coverArt id 与不同尺寸各存一份', () async {
    final (:cache, :requests) = counting();

    await cache.file('c1', uri: uri);
    await cache.file('c2', uri: uri);
    await cache.file('c1', size: 300, uri: uri);
    expect(requests, hasLength(3));

    await cache.file('c1', uri: uri);
    await cache.file('c2', uri: uri);
    await cache.file('c1', size: 300, uri: uri);
    expect(requests, hasLength(3), reason: '三个不同的缓存身份都应命中');
  });

  test('占用可被查询：按落盘字节累加，下载中的临时文件不计入', () async {
    final (:cache, :requests) = counting();
    expect(await cache.totalBytes(), 0);

    await cache.file('c1', uri: uri);
    await cache.file('c2', uri: uri);

    expect(await cache.totalBytes(), bytes.length * 2);

    // 下载中断留下的临时文件不算占用（清除时会被一并删掉）。
    final leftover = File('${dir.path}/c1.img.tmp');
    await leftover.writeAsBytes(bytes);
    expect(await cache.totalBytes(), bytes.length * 2);
  });

  test('可被整体清除：占用归零，清除后再次访问重新下载', () async {
    final (:cache, :requests) = counting();
    await cache.file('c1', uri: uri);
    await cache.file('c2', uri: uri);
    expect(await cache.totalBytes(), greaterThan(0));

    await cache.clear();

    expect(await cache.totalBytes(), 0);
    expect(await cache.file('c1', uri: uri), isNotNull);
    expect(requests, hasLength(3), reason: '清除后同一封面应重新下载');
  });

  test('cacheKey 与落盘文件名同源（界面用它判断要不要重问缓存）', () async {
    final (:cache, :requests) = counting();

    final file = await cache.file('c1', size: 300, uri: uri);

    expect(file!.path, endsWith('${cache.cacheKey('c1', size: 300)}.img'));
    expect(
      cache.cacheKey('c1', size: 300),
      isNot(cache.cacheKey('c1')),
      reason: '尺寸不同是两份缓存',
    );
  });

  test('下载失败返回 null，不抛异常（界面据此降级直连）', () async {
    final cache = CoverCache(
      directory: dir,
      fetch: (_) async => throw const SocketException('boom'),
    );

    expect(await cache.file('c1', uri: uri), isNull);
  });

  test('空响应视为失败，不留下零字节缓存', () async {
    final cache = CoverCache(directory: dir, fetch: (_) async => Uint8List(0));

    expect(await cache.file('c1', uri: uri), isNull);
    expect(await cache.totalBytes(), 0);
  });

  test('目录不可写时读写都不抛异常', () async {
    // 把目录指向一个同名文件：创建目录必然失败。
    final blocked = File('${dir.path}/blocked');
    await blocked.writeAsString('not a directory');
    final cache = CoverCache(
      directory: Directory(blocked.path),
      fetch: (_) async => bytes,
    );

    expect(await cache.file('c1', uri: uri), isNull);
    expect(await cache.totalBytes(), 0);
    await cache.clear();
  });

  test('空文件（上次写到一半）视为未命中并重新下载', () async {
    final (:cache, :requests) = counting();
    // 先制造一个与缓存文件名一致的空文件。
    final first = await cache.file('c1', uri: uri);
    await first!.writeAsBytes(const <int>[]);

    final again = await cache.file('c1', uri: uri);

    expect(again, isNotNull);
    expect(await again!.readAsBytes(), bytes);
    expect(requests, hasLength(2));
  });

  test('同一封面的并发请求合并成一次下载', () async {
    var calls = 0;
    final gate = Completer<Uint8List>();
    final cache = CoverCache(
      directory: dir,
      fetch: (_) {
        calls++;
        return gate.future;
      },
    );

    final a = cache.file('c1', uri: uri);
    final b = cache.file('c1', uri: uri);
    gate.complete(bytes);
    final results = await Future.wait([a, b]);

    expect(calls, 1);
    expect(results[0]!.path, results[1]!.path);
  });
}

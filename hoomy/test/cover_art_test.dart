import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/data/auth/auth_controller.dart';
import 'package:hoomy/data/cover/cover_cache.dart';
import 'package:hoomy/data/cover/cover_cache_provider.dart';
import 'package:hoomy/features/shared/cover_art.dart';

import 'fake_transport.dart';

/// 票据 07：`CoverArt` 的缓存接线与降级路径。
///
/// 只断言「用了哪个 ImageProvider」：缓存命中走本地文件，缓存不可用或失败时
/// 降级为直连请求，界面不崩。
///
/// 缓存要读写真磁盘，而 `testWidgets` 默认在假时钟下运行，真实 IO 不会完成，
/// 因此这些用例在 `tester.runAsync` 的真实时钟下加载。
void main() {
  /// 1×1 的有效 PNG，避免 `Image.file` 解码失败走 errorBuilder。
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  );

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hoomy_cover_art_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Widget harness(CoverCache? cache) => ProviderScope(
    overrides: [
      // 真实客户端只用来生成带认证的封面地址，不发请求。
      subsonicClientProvider.overrideWithValue(
        addressOnlyClient(),
      ),
      coverCacheProvider.overrideWithValue(cache),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: CoverArt(coverArtId: 'c1')),
      ),
    ),
  );

  /// 在真实时钟下挂载并等缓存 IO 落定，再回到测试时钟重建一帧。
  Future<void> pumpWithCache(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  ImageProvider providerOf(WidgetTester tester) =>
      tester.widget<Image>(find.byType(Image)).image;

  testWidgets('命中缓存时用本地文件，不请求网络', (tester) async {
    final cache = CoverCache(directory: dir, fetch: (_) async => png);

    await pumpWithCache(tester, harness(cache));

    expect(providerOf(tester), isA<FileImage>());
  });

  testWidgets('第二次构建同一封面不再下载', (tester) async {
    var requests = 0;
    final cache = CoverCache(
      directory: dir,
      fetch: (_) async {
        requests++;
        return png;
      },
    );

    await pumpWithCache(tester, harness(cache));
    expect(requests, 1);

    // 同一棵树上重建：缓存查询被复用，不再发起下载。
    await pumpWithCache(tester, harness(cache));
    expect(requests, 1);
    expect(providerOf(tester), isA<FileImage>());
  });

  testWidgets('缓存被清除后再次访问同一封面：重新下载并仍用本地文件显示', (tester) async {
    var requests = 0;
    final cache = CoverCache(
      directory: dir,
      fetch: (_) async {
        requests++;
        return png;
      },
    );

    await pumpWithCache(tester, harness(cache));
    expect(providerOf(tester), isA<FileImage>());
    expect(requests, 1);

    // 设置页手动清除缓存（票据 15）。缓存读写是真实 IO，放在真实时钟下。
    await tester.runAsync(() async {
      await cache.clear();
      // 卸载封面再重新挂载，模拟「清除后界面再次访问同一封面」；同时清掉
      // Flutter 的解码缓存，否则第一棵树留下的旧文件条目会干扰观察。
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      imageCache.clear();
      imageCache.clearLiveImages();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    await pumpWithCache(tester, harness(cache));

    expect(providerOf(tester), isA<FileImage>(), reason: '封面照常显示');
    expect(requests, 2, reason: '清除后应重新下载并重新落盘');
  });

  testWidgets('缓存失败时降级为直连请求', (tester) async {
    final cache = CoverCache(
      directory: dir,
      fetch: (_) async => throw const SocketException('boom'),
    );

    await pumpWithCache(tester, harness(cache));

    expect(providerOf(tester), isA<NetworkImage>());
  });

  testWidgets('没有缓存能力时直接请求服务端', (tester) async {
    await tester.pumpWidget(harness(null));
    await tester.pump();

    expect(providerOf(tester), isA<NetworkImage>());
  });

  testWidgets('没有封面 id 时显示占位，不构建图片', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subsonicClientProvider.overrideWithValue(
            addressOnlyClient(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CoverArt(coverArtId: null)),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cover/cover_cache_provider.dart';
import '../../data/session/session_providers.dart';

/// 经 getCoverArt 拉取的封面图（服务端已解析文件内嵌封面）。
///
/// 优先读磁盘缓存（ADR-0006）：同一 `coverArt` id 命中缓存时不再发起请求。
/// 缓存不可用或读写失败时**降级为直接请求**，界面不会因此崩溃或空白。
///
/// 界面基本无圆角（`CONTEXT.md`「方块化」），封面一律直角。
class CoverArt extends ConsumerStatefulWidget {
  const CoverArt({super.key, this.coverArtId, this.size});

  final String? coverArtId;
  final int? size;

  @override
  ConsumerState<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends ConsumerState<CoverArt> {
  /// 当前缓存查询；曲目／尺寸变化时重建。
  Future<File?>? _cached;
  String? _cacheKey;

  @override
  Widget build(BuildContext context) {
    // 没有封面 id 就没有可取的图：这是曲目的属性，不是「有没有会话」的第二形态，
    // 所以先短路，再向会话要地址（ADR-0015：会话之上没有判空分支）。
    final id = widget.coverArtId;
    if (id == null || id.isEmpty) return _placeholder(context);

    final session = ref.watch(sessionProvider);
    final cache = ref.watch(coverCacheProvider);

    final uri = session.coverArtUri(id, size: widget.size);
    if (cache == null) return _network(context, uri);

    final key = cache.cacheKey(id, size: widget.size);
    if (_cacheKey != key) {
      _cacheKey = key;
      _cached = cache.file(id, size: widget.size, uri: uri);
    }

    return FutureBuilder<File?>(
      future: _cached,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder(context);
        }
        final file = snapshot.data;
        if (file == null) {
          // 缓存拿不到：降级为直连请求（票据 07 的降级路径）。
          return _network(context, uri);
        }
        return Image.file(
          file,
          fit: BoxFit.cover,
          // 缓存文件损坏时同样降级直连，而不是把错误抛到界面上。
          errorBuilder: (_, _, _) => _network(context, uri),
        );
      },
    );
  }

  /// 直连服务端；网络失败时退回占位图。
  Widget _network(BuildContext context, Uri uri) => Image.network(
    uri.toString(),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => _placeholder(context),
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : _placeholder(context),
  );

  Widget _placeholder(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.secondaryContainer,
    alignment: Alignment.center,
    child: Icon(
      Icons.music_note_outlined,
      color: Theme.of(context).colorScheme.onSecondaryContainer,
    ),
  );
}

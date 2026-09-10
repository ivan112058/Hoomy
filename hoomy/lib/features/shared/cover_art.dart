import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';

/// 经 getCoverArt 拉取的封面图（服务端已解析文件内嵌封面）。
class CoverArt extends ConsumerWidget {
  const CoverArt({super.key, this.coverArtId, this.size, this.borderRadius});

  final String? coverArtId;
  final int? size;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(subsonicClientProvider);
    final id = coverArtId;
    if (client == null || id == null || id.isEmpty) {
      return _placeholder(context);
    }
    final image = Image.network(
      client.coverArtUri(id, size: size).toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(context),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(context),
    );
    return borderRadius == null
        ? image
        : ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _placeholder(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.secondaryContainer,
        alignment: Alignment.center,
        child: Icon(Icons.music_note_outlined,
            color: Theme.of(context).colorScheme.onSecondaryContainer),
      );
}

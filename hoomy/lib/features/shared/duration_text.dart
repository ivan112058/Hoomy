/// 时长的界面文案，歌曲行、播放页进度条、队列行共用同一份口径。
library;

/// 把秒数或时长写成 `m:ss`，可选一个前缀（例如剩余时长的 `-`）。
///
/// 时长未知（null）时返回 null，调用方据此决定是否占位。
String? formatPlaybackDuration(Duration? duration, {String prefix = ''}) {
  if (duration == null) return null;
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$prefix$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 把服务端给的秒数写成 `m:ss`；秒数缺失时返回 null。
String? formatMetadataDuration(int? seconds) => seconds == null
    ? null
    : formatPlaybackDuration(Duration(seconds: seconds));

import '../../data/subsonic/models.dart';

/// 歌曲副标题：`CONTEXT.md`「列表行」规定的「歌手 - 专辑」。
///
/// 缺一边时只显示存在的一边；两边都缺返回 null（调用方据此决定是否占位）。
/// 歌曲行与播放条共用同一份文案，避免两处各写一遍。
String? songSecondaryText(SubsonicSong? song) {
  if (song == null) return null;
  final parts = [
    song.artist,
    song.album,
  ].where((part) => part != null && part.isNotEmpty).cast<String>().toList();
  return parts.isEmpty ? null : parts.join(' - ');
}

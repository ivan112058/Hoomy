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

/// 歌曲的「歌手」一行：只要歌手，没有歌手时退回专辑。
///
/// 迷你播放条位置窄，用不下「歌手 - 专辑」（那是 `CONTEXT.md`「列表行」的
/// 规矩）；但歌手/专辑的取舍规则与 [songSecondaryText] 放在一处，避免两处
/// 各写一遍后各自演化。
String? songArtistText(SubsonicSong? song) {
  if (song == null) return null;
  final artist = song.artist;
  if (artist != null && artist.isNotEmpty) return artist;
  final album = song.album;
  return (album != null && album.isNotEmpty) ? album : null;
}

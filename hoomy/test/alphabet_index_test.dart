import 'package:flutter_test/flutter_test.dart';

import 'package:hoomy/core/alphabet/alphabet.dart';
import 'package:hoomy/data/subsonic/models.dart';
import 'package:hoomy/features/songs/song_search.dart';

/// 分组键与搜索键的纯逻辑接缝（ADR-0005 / ADR-0009）。
///
/// 界面上的分组头与 A–Z 快捷栏都建立在 [alphabetGroupKey] 之上，
/// 因此这里覆盖中英文、数字、符号、空串、空白与多音字姓氏。
void main() {
  group('分组键', () {
    test('中文取首字拼音首字母，而不是整串首字母', () {
      expect(alphabetGroupKey('五条人'), 'W');
      expect(alphabetGroupKey('周杰伦'), 'Z');
      expect(alphabetGroupKey('叶惠美'), 'Y');
    });

    test('纯英文取首字母并统一大写', () {
      expect(alphabetGroupKey('Adele'), 'A');
      expect(alphabetGroupKey('The Beatles'), 'T');
      expect(alphabetGroupKey('beyond'), 'B');
    });

    test('数字、符号与非 ASCII 字母一律入 #', () {
      expect(alphabetGroupKey('123'), '#');
      expect(alphabetGroupKey('#hash'), '#');
      expect(alphabetGroupKey('éclair'), '#');
    });

    test('先 trim 再取首字符', () {
      expect(alphabetGroupKey('  空格 首'), 'K');
      expect(alphabetGroupKey('  Adele'), 'A');
    });

    test('空串与纯空白入 #', () {
      expect(alphabetGroupKey(''), '#');
      expect(alphabetGroupKey('   '), '#');
    });

    test('中英混合取中文首字', () {
      expect(alphabetGroupKey('周杰伦 Jay'), 'Z');
    });

    test('多音字姓氏不落错组', () {
      expect(alphabetGroupKey('单田芳'), 'S');
      expect(alphabetGroupKey('曾毅'), 'Z');
      expect(alphabetGroupKey('区瑞强'), 'O');
      expect(alphabetGroupKey('仇晓'), 'Q');
      expect(alphabetGroupKey('查海生'), 'Z');
      expect(alphabetGroupKey('解晓东'), 'X');
    });
  });

  group('分组', () {
    test('按 A–Z、# 的顺序排列，组内保持原顺序', () {
      final sections = buildAlphabetSections(
        ['周杰伦', 'Adele', '123', 'Beyond', '五条人'],
        keyOf: (name) => name,
      );

      expect(sections.map((s) => s.key).toList(), ['A', 'B', 'W', 'Z', '#']);
      expect(sections.first.items, ['Adele']);
      expect(sections.last.items, ['123']);
    });

    test('同一组内保持传入顺序', () {
      final sections = buildAlphabetSections(
        ['周杰伦', '张惠妹', '周传雄'],
        keyOf: (name) => name,
      );

      expect(sections.single.key, 'Z');
      expect(sections.single.items, ['周杰伦', '张惠妹', '周传雄']);
    });

    test('空列表得到空分组', () {
      expect(buildAlphabetSections<String>([], keyOf: (name) => name), isEmpty);
    });
  });

  group('歌曲本地过滤', () {
    const songs = [
      SubsonicSong(id: 's1', title: '晴天', artist: '周杰伦', album: '叶惠美'),
      SubsonicSong(
        id: 's2',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
      ),
    ];

    List<String> idsOf(List<SubsonicSong> result) =>
        result.map((song) => song.id).toList();

    test('匹配歌名且大小写不敏感', () {
      expect(idsOf(filterSongsByQuery(songs, 'bohemian')), ['s2']);
    });

    test('歌手与专辑也参与匹配', () {
      expect(idsOf(filterSongsByQuery(songs, '叶惠美')), ['s1']);
      expect(idsOf(filterSongsByQuery(songs, 'queen')), ['s2']);
    });

    test('查询两侧空白被忽略', () {
      expect(idsOf(filterSongsByQuery(songs, '  晴  ')), ['s1']);
    });

    test('空查询与纯空白查询原样返回全部，顺序不变', () {
      expect(filterSongsByQuery(songs, ''), songs);
      expect(filterSongsByQuery(songs, '   '), songs);
    });

    test('无匹配返回空列表', () {
      expect(filterSongsByQuery(songs, '不存在'), isEmpty);
    });
  });

  group('歌曲搜索键', () {
    const song = SubsonicSong(
      id: 's1',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
    );

    test('歌名、歌手、专辑都能命中', () {
      expect(songSearchText(song), contains('晴天'));
      expect(songSearchText(song), contains('周杰伦'));
      expect(songSearchText(song), contains('叶惠美'));
    });

    test('缺歌手或专辑时不产生多余空白键', () {
      const bare = SubsonicSong(id: 's2', title: '未知曲目');
      expect(songSearchText(bare), '未知曲目');
    });
  });
}

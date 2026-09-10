/// 字母分组：把名称归入 A–Z 或 `#`（ADR-0005 / ADR-0009）。
///
/// 纯逻辑、无 Flutter 依赖：分组头与 A–Z 快捷栏都建立在
/// [alphabetGroupKey] 之上，单元测试与界面测试共用同一处规则。
library;

import 'package:lpinyin/lpinyin.dart';

/// 归入「其它」组时的组键。
const alphabetOtherKey = '#';

/// 全部组键，按界面呈现顺序排列：A–Z、`#`。
final List<String> alphabetKeys = List.unmodifiable([
  for (var c = 0x41; c <= 0x5A; c++) String.fromCharCode(c),
  alphabetOtherKey,
]);

/// 多音字姓氏修正表。
///
/// 两个拼音包都不做姓氏读音（ADR-0009），这里只收录**已发现的错组**，
/// 不追求完整姓氏库。修正按名称首字匹配，所以同一个字作普通用字时也会
/// 被修正（「曾经」会落到 Z），这是已知且可接受的缺陷。
///
/// 已知缺口：本表结构上只认单字，两字姓氏（如 ADR-0009 举例的「尉迟」）
/// 表达不了，遇到时会按首字读音落组。
const _polyphonicSurnameInitials = <String, String>{
  '单': 'S', // 拼音包给 dan；单田芳应入 S
  '曾': 'Z', // 拼音包给 ceng；曾毅应入 Z
  '区': 'O', // 拼音包给 qu；区瑞强应入 O
  '仇': 'Q', // 拼音包给 chou；仇晓应入 Q
  '查': 'Z', // 拼音包给 cha；查海生应入 Z
  '解': 'X', // 拼音包给 jie；解晓东应入 X
};

/// 取名称的分组键：`A`–`Z` 之一，或 `#`。
///
/// 规则：
/// 1. 先 `trim()`，空串入 `#`；
/// 2. 首字命中多音字姓氏修正表时直接用修正结果；
/// 3. 否则取**首字拼音的首字母**（`五条人` → `wu` → `W`，不是 `wtr`），
///    结果不落在 A–Z 的（数字、符号、带音标字母）一律入 `#`。
String alphabetGroupKey(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return alphabetOtherKey;

  final firstChar = String.fromCharCode(trimmed.runes.first);
  final corrected = _polyphonicSurnameInitials[firstChar];
  if (corrected != null) return corrected;

  final pinyin = PinyinHelper.getFirstWordPinyin(trimmed);
  if (pinyin.isEmpty) return alphabetOtherKey;

  final initial = String.fromCharCode(pinyin.runes.first).toUpperCase();
  final code = initial.runes.first;
  final isAsciiUppercase = code >= 0x41 && code <= 0x5A;
  return isAsciiUppercase ? initial : alphabetOtherKey;
}

/// 一个字母分组：组键 + 组内条目（保持传入顺序）。
class AlphabetSection<T> {
  const AlphabetSection({required this.key, required this.items});

  /// `A`–`Z` 或 `#`。
  final String key;

  final List<T> items;

  int get length => items.length;
}

/// 把 [items] 按 [keyOf] 的分组键分入 A–Z 与 `#`，返回非空组。
///
/// 组间按 A–Z、`#` 排列，**组内保持传入顺序** —— 服务端的自然顺序
/// 已是有意义的顺序，分组只负责切段，不负责重排。
List<AlphabetSection<T>> buildAlphabetSections<T>(
  List<T> items, {
  required String Function(T item) keyOf,
}) {
  final buckets = <String, List<T>>{};
  for (final item in items) {
    buckets.putIfAbsent(alphabetGroupKey(keyOf(item)), () => <T>[]).add(item);
  }

  return [
    for (final key in alphabetKeys)
      if (buckets[key] case final group?) AlphabetSection(key: key, items: group),
  ];
}

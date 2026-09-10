# 拼音首字母分组 与 media_kit 后台播放/系统媒体控制 调研（面向 Hoomy）

- 调研日期：2026-09-10
- 调研方式：pub.dev 官方 API（`/api/packages/<name>`、`/api/packages/<name>/score`、`/api/search`）、包归档文件（`api/archives/*.tar.gz`）直接解包审阅、GitHub 仓库源码/Issue/README、Flutter 官方与 Apple/Android/Microsoft 官方文档，并在本机（Dart 3.13.2 / Flutter 3.47.2 / macOS）实测运行。
- 目标平台口径：iOS、Android TV、macOS、Windows（不含 Android 手机、Linux、Web）。
- 说明：每条结论标注来源 URL 与置信度；凡是**本机实测**的结论单独标注「实测」，它不是外部来源，但可复现。未能确认的一律写入文末「未能核实」清单。

---

## 结论速查

### 第一组：中文 → 拼音首字母

| 方案 | 最新版本 | 发布日 | 纯 Dart？ | 四平台可用 | 维护状态 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `lpinyin` | **2.0.3** | 2021-05-11 | ✅ 完全纯 Dart，`dependencies` 为空 | ✅ | 已实质停更（GitHub 最后 push 2023-05-06） | 139 likes / 160 points；实测 Dart 3.13 可解析可运行 |
| `pinyin` | **3.3.0** | 2024-04-16 | ✅ 纯 Dart，运行期无依赖 | ✅ | 半维护（仓库 2026-03 有活动，但 2024-04 后无新版本） | 19 likes / 160 points；数据文件 4.08 MB |
| `pinyin_pro_flutter` | 1.0.3 | 2026-05-30 | ✅ 纯 Dart | ✅ | 新包，无历史 | 2 likes / 155 points |
| `pinyindart` | 0.0.1 | 2026-03-16 | ✅ 纯 Dart | ✅ | 极早期（0.0.1） | 0 likes / 155 points |
| `xue_hua_pinyin` | 1.1.3 | 2026-08-13 | ❌ Rust + FFI（`is:plugin`） | 需每平台编译 | 新包 | 0 likes / 145 points，引入 Rust 工具链成本 |
| `bpmf_py` | 0.2.0 | 2024-03-15 | ✅ 纯 Dart | ✅ | 低频维护 | 注音/拼音互转，非首字母专用 |
| `chinese_pinyin` | — | — | — | — | **pub.dev 上不存在（API 404）** | 无法核实该包存在 |
| `flutter_pinyin` | — | — | — | — | **pub.dev 上不存在（API 404）** | 无法核实该包存在 |

### 第二组：后台播放与系统媒体控制

| 能力 | media_kit 1.2.6 是否提供 | 需要补什么 |
| --- | --- | --- |
| 播放/暂停/seek/上一首/下一首/位置流 | ✅ 全部有 | 无 |
| iOS 后台播放 | ❌ 不提供、不文档化 | `UIBackgroundModes: audio` + `audio_service`（+ `audio_session`） |
| iOS/macOS 锁屏·控制中心「正在播放」与远程控制 | ❌ 零实现（源码无 `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`） | `audio_service`（其 darwin 原生实现覆盖） |
| Android 通知媒体控制 + 前台服务 | ❌ 不提供 | `audio_service` |
| Windows SMTC | ❌ 不提供 | `audio_service_win` 或 `smtc_windows` 或 `flutter_media_session` |
| 带 query string 的 URL（`stream.view?id=..&u=..&t=..&s=..`） | ✅ 应可用（实测 Dart 层原样透传） | 无需额外处理；注意 HTTPS 的 TLS 1.3 限制 |

---

# 第一组：中文拼音首字母（A-Z 分组）

## 1.1 可用包与其维护状态

pub.dev 搜索 `pinyin` 得到 10 个包：`pinyin`、`lpinyin`、`string_util_xx`、`pinyin_pro_flutter`、`pinyindart`、`xue_hua_pinyin`、`bpmf_py`、`writing_guidelines`、`flutter_multi_formatter`、`hy_pinyin`。
来源：<https://pub.dev/api/search?q=pinyin>（实测）　置信度：高。

**`lpinyin`**
- 最新版 **2.0.3**，发布于 **2021-05-11**；`environment.sdk: ">=2.12.0-259.9.beta <3.0.0"`；`pubspec.yaml` 中**没有任何 `dependencies`**。
  - <https://pub.dev/api/packages/lpinyin>
- pub.dev 打分：139 likes、160/160 points、35.9k downloads；标签含 `is:dart3-compatible`（尽管 SDK 上界写的是 `<3.0.0`）。
  - <https://pub.dev/packages/lpinyin>、<https://pub.dev/api/packages/lpinyin/score>
- GitHub `flutterchina/lpinyin`：367 stars，**最后 push 2023-05-06**，未归档。CHANGELOG 最后一条是 2.0.3，内容为 `* TODO: some updates.`（即为占位）。
  - <https://api.github.com/repos/flutterchina/lpinyin>　<https://github.com/flutterchina/lpinyin/blob/master/CHANGELOG.md>
- **结论：功能可用但仍在上架，实质已停止功能维护（自 2021 年起无新版本）。**置信度：高。

**`pinyin`（sun-jiao/dart-pinyin）**
- 最新版 **3.3.0**，发布于 **2024-04-16**；`environment.sdk: ">=2.12.0 <4.0.0"`，运行期无依赖；由 verified publisher `sunjiao.net` 发布。
  - <https://pub.dev/api/packages/pinyin>
- 打分：19 likes、160/160 points、7.97k downloads；全平台标签 + `is:dart3-compatible`。
  - <https://pub.dev/api/packages/pinyin/score>
- GitHub `sun-jiao/dart-pinyin`：11 stars，仓库 `pushed_at` 2026-03-24，但 **CHANGELOG 与 pub 上的最后版本都停在 3.3.0（2024-04-16）**，即近两年无版本发布。
  - <https://github.com/sun-jiao/dart-pinyin/blob/main/CHANGELOG.md>　<https://api.github.com/repos/sun-jiao/dart-pinyin>
- 该包 README 自述为 `lpinyin` 原作者（@Sky24n 等 flutterchina 成员）作品的延续，并说明数据来源为 Unihan / Wiktionary / 汉典 / mozillazg/pinyin-data。
  - <https://pub.dev/packages/pinyin>
- **结论：是 `lpinyin` 的事实后继者，Dart 3 与四平台均安全，但更新节奏已放缓。**置信度：高。

**其他**
- `pinyin_pro_flutter` 1.0.3（2026-05-30，纯 Dart，2 likes/155 points）：<https://pub.dev/api/packages/pinyin_pro_flutter>
- `pinyindart` 0.0.1（2026-03-16）：<https://pub.dev/api/packages/pinyindart>
- `xue_hua_pinyin` 1.1.3（2026-08-13）：pub 标签为 `is:plugin` + `is:built-in-kotlin`，README 自述「powered by Rust」，需 Rust/FFI 构建链：<https://pub.dev/api/packages/xue_hua_pinyin/score>
- `hy_pinyin` 2.0.0（2022-08-04，SDK `<3.0.0`）：<https://pub.dev/api/packages/hy_pinyin>
- `chinese_pinyin`、`flutter_pinyin`：`https://pub.dev/api/packages/chinese_pinyin` 与 `.../flutter_pinyin` 均返回 404（`NoSuchKey`）。**这两个包在 pub.dev 上不存在**；若你在别处见过同名项目，它们未发布到 pub.dev，本项目无法通过 `pub` 依赖。置信度：高（针对「pub.dev 上不存在」这一断言）。

## 1.2 哪些是纯 Dart（四平台通吃）

- **纯 Dart、零原生代码、零平台通道，因此 iOS/Android(TV)/macOS/Windows 通吃**：`lpinyin`、`pinyin`、`pinyin_pro_flutter`、`pinyindart`、`bpmf_py`。
  - 判据一（实测）：解包 `lpinyin-2.0.3.tar.gz` 后 `grep '^import' lib -r` 的结果**只包含包内 `src/` 相对导入**，没有任何 `package:flutter/*`、`dart:ffi` 或 MethodChannel；`pubspec.yaml` 无 `dependencies`、无 `flutter.plugin` 段（0.0.1 时代曾是 Android 插件，但 1.0.0 之后已去除）。
  - 判据二：pub.dev 平台标签对这几个包均列出全部 6 个平台，且不带 `is:plugin`。
    <https://pub.dev/api/packages/lpinyin/score>、<https://pub.dev/api/packages/pinyin/score>
  - 置信度：高。
- **含原生的只有 `xue_hua_pinyin`（Rust FFI，pub 标签 `is:plugin`）**，以及历史上 `lpinyin 0.0.x`（Android 插件，已废弃）。
- `hy_pinyin` 虽为纯 Dart，但 SDK 上界 `<3.0.0` 且 2022 年后无更新，不建议新项目使用。

## 1.3 `lpinyin` 是否还能用、实现方式与体积代价

**能用。**（实测）在本机 Dart 3.13.2 / Flutter 3.47.2 下，新建工程写 `lpinyin: ^2.0.3` 后 `dart pub get` 成功解析并下载 `lpinyin 2.0.3`，`dart run` 调用 `PinyinHelper.getShortPinyin` 正常返回，无编译或运行期错误。这与 pub.dev 给它的 `is:dart3-compatible` 标签一致。置信度：高。
（推测机制：pub 对纯 Dart 包会按较低 language version 解析，`<3.0.0` 的上界未阻止 Dart 3 消费该包——此处仅陈述实测结果，不展开 pub 内部规则。）

**实现方式：自建词典 + 词组最长匹配消歧，没有分词库、没有 ICU。**（实测，基于 2.0.3 归档源码）
- `lib/src/dict_data.dart` 共 **390,797 字节**，是三个 `const List<String>`：
  - `pinyinDict`：**20,902** 条「单字=拼音（多音用逗号分隔）」，如 `'耆=qí,shì'`；
  - `multiPinyinDict`：**824** 条词组级多音字消歧规则；
  - `chineseDict`：**2,532** 条 繁→简 映射。
- `lib/src/pinyin_helper.dart` 的算法是：逐字查 `pinyinDict`；遇到多音字时从当前位置向后按长度窗口在 `multiPinyinMap` 里做**最长匹配**（`for (int end = minMultiLength ...)`）以整词定音；多音字仍无法判定时取第一个读音（`_pinyin.split(...)[0]`）。
- 支持用户字典：`PinyinHelper.addPinyinDict` / `addMultiPinyinDict` / `ChineseHelper.addChineseDict`（README 有示例）。
  <https://pub.dev/packages/lpinyin>

**体积代价**

| 包 | pub 归档（gzip） | 解包后源码体积 | 最大数据文件 |
| --- | --- | --- | --- |
| `lpinyin` 2.0.3 | **124 KB** | `lib/` 共 **416 KB** | `dict_data.dart` 390,797 B |
| `pinyin` 3.3.0 | **1.32 MB** | `lib/` 共 **4.08 MB** | `phrase_simp_to_trad.dart` 1,396,324 B；`phrase_map.dart` 1,320,548 B；`pinyin_map.dart` 1,102,617 B |

（实测：`ls -l` 归档内文件 + `tar tzvf` 排序。注意这些是**源码**体积；AOT 编译后字符串常量会进入 snapshot，实际增量应小于源码体积但同量级，未实测最终 app 体积增量。）

结论：**只做「首字母分组」这一件事时，`lpinyin` 的体积代价（约 0.4 MB 源码 / 124 KB 压缩）明显低于 `pinyin`（约 4 MB 源码 / 1.3 MB 压缩）**，因为后者附带了完整的繁体转换与词组库。置信度：高（体积为实测），「最终 app 体积增量」未实测。

**性能（实测，本机 macOS，Debug 模式下 `dart run`）**

| 指标 | `lpinyin` 2.0.3 | `pinyin` 3.3.0 |
| --- | --- | --- |
| 首次调用（含词典初始化） | 19 ms | 40 ms |
| 2000 条曲名 `getShortPinyin` 累计 | 22 ms | 20 ms |

即：初始化一次性开销 ~20–40 ms，之后约 **0.01 ms/条**。万首曲库冷启动一次性转换约 0.1 秒量级，可忽略。置信度：中（单机单次测量，未做统计显著性）。

## 1.4 多音字与姓氏读音（实测对照）

用同一批姓名/词语同时跑 `lpinyin` 与 `pinyin` 的 `getFirstWordPinyin`（正确读音以《现代汉语词典》姓氏读法为准）：

| 词 | 正确读音 | `lpinyin` | `pinyin` | 首字母是否出错 |
| --- | --- | --- | --- | --- |
| 五条人 | wǔ | wu | wu | 否 |
| 长城 | cháng | chang | chang | 否 |
| 成都 | chéng | cheng | cheng | 否 |
| 重庆 | chóng | chong | chong | 否 |
| 音乐 | yīn | yin | yin | 否 |
| 银行 | háng | yin | yin | 否 |
| 单田芳（姓 shàn） | shàn | **dan** | **dan** | **是（D↔S）** |
| 曾国藩（姓 zēng） | zēng | **ceng** | zeng ✅ | **lpinyin 出错（C↔Z）** |
| 尉迟恭（尉迟 yù chí） | yù | yu ✅ | **wei** | **pinyin 出错（W↔Y）** |
| 仇英（姓 qiú） | qiú | **chou** | **chou** | **是（C↔Q）** |
| 区瑞强（姓 ōu） | ōu | **qu** | **qu** | **是（Q↔O）** |
| 查良镛（姓 zhā） | zhā | **cha** | **cha** | **是（C↔Z）** |
| 解晓东（姓 xiè） | xiè | **jie** | **jie** | **是（J↔X）** |
| 朴树（姓 piáo） | piáo | pu | pu | 否（首字母同为 P） |
| 乐乐（姓 yuè） | yuè | **le** | **le** | **是（L↔Y）** |
| 哪吒 | né | na | na | 否 |

**结论：两个包都做「词组消歧」，不做「姓氏读音库」。**对 A-Z 分组而言，姓氏导致的**首字母级**错误是真实存在的（上表标红项），其中 `lpinyin` 与 `pinyin` 各有各的错法（`曾国藩` 只有 `pinyin` 对，`尉迟恭` 只有 `lpinyin` 对）。若产品能接受「少数姓氏歌手被分错组」，无需额外工作；若要正确，需要自行维护一张姓氏读音覆盖表并在调用前替换。
置信度：高（实测，可复现脚本见文末）。两个包都提供 `addPinyinDict` / `addMultiPinyinDict` 作为官方扩展点，可用来注入姓氏读音。

## 1.5 是否内置 ICU 转写 / `intl` 能不能转写 / 平台 API

- **`intl` 不能做中文→拉丁转写。**（实测）下载 `intl 0.20.3`（2026-06-25，<https://pub.dev/api/packages/intl>）归档后 `grep -ri transliterat lib/` **零命中**；`Intl` 类的成员只有 `date/gender/locale/message/plural/select/...`，没有转写 API。<https://pub.dev/documentation/intl/latest/intl/Intl-class.html>。`intl` 里出现的 "ICU" 仅指 ICU MessageFormat 语法子集（`lib/message_format.dart` 注释）。置信度：高。
- **Dart 标准库没有转写能力。**`dart:core` / `dart:convert` 只提供 Unicode 编解码与大小写等基础操作，没有 ICU 转写入口。置信度：高。
- **Flutter 引擎自带 ICU 数据，但没有对 Dart 暴露转写 API。**（实测）本机 Flutter SDK 中存在引擎资源 `bin/cache/artifacts/engine/darwin-x64/icudtl.dat` 等文件；但 `dart:ui` 未提供任何 `transliterate` 入口。置信度：中（「未暴露 API」为高；「引擎如何链接 ICU」未逐平台核实）。
- **各平台确有原生转写 API，但没有现成 Flutter 插件封装：**
  - iOS / macOS：`CFStringTransform` 支持 `kCFStringTransformMandarinLatin`（Apple 文档原文：*"The identifier of a transform to transliterate text to Latin from ideographs interpreted as Mandarin Chinese. This transform is not reversible."*）与 `kCFStringTransformToLatin`；Apple 文档还写明 macOS 10.4+ 可直接使用任意 ICU transform ID。
    <https://developer.apple.com/documentation/corefoundation/transform-identifiers-for-cfstringtransform>　置信度：高（Apple 官方文档 JSON，已核对原文）。
  - Android：`android.icu.text.Transliterator`（如 `Han-Latin`），文档表格中所有成员标注 `data-version-added="29"`，即 **API 29（Android 10）起可用**。
    <https://developer.android.com/reference/android/icu/text/Transliterator>　置信度：高。
  - Windows：ICU 自 Windows 10 1703 起集成进系统，以 `icuuc.dll`/`icuin.dll`（1903 起合并为 `icu.dll`）暴露**仅 C API**，其中 `icuin` 即 ICU 的 i18n 组件（转写 `utrans_*` 属于该组件），因此理论上可通过 FFI 调用；但**本项目未实测**，且需要自行处理 DLL 与版本差异。
    <https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu->　置信度：中。
  - 采用平台 API 意味着**四套实现 + 平台通道**，对 Hoomy 这种四平台项目是明显更重的方案；且 Windows 上没有现成封装。
- 在 pub.dev 上未找到任何把这些平台转写 API 封装好的包（搜索关键词 `transliterat`/`icu` 无相关结果，`romanize`/`phonemize` 是反向依赖 Dart 实现的）。

## 1.6 「曲名首字母分组」的社区实践

- **没有找到专门做「中文音乐库 A-Z 分组」的包。**社区的做法是「拼音包算首字母 → 自己分组 → 交给通用 A-Z 索引列表控件」。
- 最贴近的组合是 **`alphabet_index_listview`**（v1.0.36，**2025-07-25**，4 likes / 145 points，平台标签覆盖 android/ios/windows/linux/macos/web，`is:dart3-compatible`），其依赖列表**直接包含 `lpinyin`**，自述为「a-z indexed listview, based on CustomScrollView and ListView, also provide a stick header listview」。
  <https://pub.dev/api/packages/alphabet_index_listview>、<https://pub.dev/api/packages/alphabet_index_listview/score>、<https://github.com/flappygod/alphabet_index_listview>　置信度：高。
- pub.dev 上依赖 `lpinyin` 的包还有 `city_pickers`、`contactor_picker`、`address_selector_for_chinese`、`alphabet_index_listview` 等，全部是「列表按拼音首字母分组 + 索引跳转」这类场景（通讯录/城市选择/字母索引列表），可作为该用法的旁证。
  <https://pub.dev/api/search?q=dependency%3Alpinyin>　置信度：中（只能证明它们依赖 lpinyin，未逐个审阅其用法）。
- 依赖 `pinyin` 的包是 `romanize`（0.0.3，2025-12-26）与 `phonemize`（1.0.0，2026-05-07），属于罗马化/音素化方向，不是 A-Z 分组。
  <https://pub.dev/api/packages/romanize>、<https://pub.dev/api/packages/phonemize>
- 滚动定位侧，`scrollable_positioned_list`（0.3.8，2023-05-08）与 `flutter_sticky_header`（0.8.0，2025-05-21）是常见的跳转/吸顶实现，但它们与拼音无关，只是配合使用。
  <https://pub.dev/api/packages/scrollable_positioned_list>、<https://pub.dev/api/packages/flutter_sticky_header>

## 1.7 对 Hoomy 的落地建议（基于上述事实）

1. **用 `lpinyin` 或 `pinyin` 均可，二选一取决于体积 vs 数据质量**：只要首字母、且希望省体积 → `lpinyin 2.0.3`（124 KB 压缩）；希望数据更新、繁体/注音能力更全、愿意接受 1.3 MB 压缩 → `pinyin 3.3.0`。两者都是纯 Dart，iOS/Android TV/macOS/Windows 零平台配置。
2. **注意 API 语义与需求不符的坑（实测）**：`getShortPinyin('五条人')` 返回的是**全部首字母** `"wtr"`（多字串接），不是 `"W"`。要拿 A-Z 分组键，必须取 `getFirstWordPinyin(name).substring(0,1)` 或 `getShortPinyin(name).substring(0,1)` 再做 `toUpperCase()`。
3. **非中文首字符原样返回（实测）**：`"The Beatles"` → `getShortPinyin` 返回 `"The Beatles"`、`getFirstWordPinyin` 返回 `"T"`；`"123"` → `"1"`；**前导空格会被保留**（`"  空格 首"` → `"  kg s"`、`getFirstWordPinyin` 返回 `" "`）；空串返回空串。因此分组前必须 `trim()` + 用正则判定 `A-Z`，否则落入 `#` 兜底组。这正好对应常见的 `#` 分组需求。
4. **姓氏读音自己兜底**：见 1.4 表。两个包都支持 `addMultiPinyinDict`，可维护一张「姓氏 → 读音」补丁表，在 A-Z 分组这一步（只在启动/同步时算一次）覆盖。
5. **只在入库时算一次并缓存**：实测 ~0.01 ms/条，且首字母结果与本地化无关，建议随歌曲元数据落库，A-Z 列表直接读缓存列，避免每次滚动都重算。

---

# 第二组：media_kit 的后台播放与系统媒体控制

## 2.1 `media_kit` 版本与 `Player` API

- **`media_kit` 最新稳定版 1.2.6，发布于 2025-12-13**，`environment.sdk: ">=3.1.0 <4.0.0"`，912 likes / 140 分，仓库 `media-kit/media-kit`（1811 stars，`pushed_at` 2026-08-30）。
  <https://pub.dev/api/packages/media_kit>、<https://pub.dev/api/packages/media_kit/score>、<https://api.github.com/repos/media-kit/media-kit>　置信度：高。
- 配套包：`media_kit_video` 2.0.1（2025-12-02）、`media_kit_libs_audio` 1.0.7（2025-10-05）、`media_kit_libs_video` 1.0.7（2025-10-05）。
  <https://pub.dev/api/packages/media_kit_video>、<https://pub.dev/api/packages/media_kit_libs_audio>
- 最近版本改动（CHANGELOG）：1.2.6/1.2.5/1.2.4 均为 `fix(windows): long file path support`；1.2.3 有 `feat: add isDefault property to Track`；**1.2.0 是一次大重构**（NativeCallable/Initializer、`PlayerConfiguration.async` 等）。
  <https://github.com/media-kit/media-kit/blob/main/media_kit/CHANGELOG.md>　置信度：高。
- **`Player` 公开 API（从 pub.dev API 文档抓取的成员全集）**：`open`、`play`、`pause`、`playOrPause`、`stop`、`seek`、`next`、`previous`、`jump`、`add`、`remove`、`move`、`setPlaylistMode`、`setShuffle`、`setRate`、`setVolume`、`setPitch`、`setAudioTrack`、`setSubtitleTrack`、`setVideoTrack`、`setAudioDevice`、`screenshot`、`dispose`，以及 `state` / `stream` / `streams`。
  <https://pub.dev/documentation/media_kit/latest/media_kit/Player-class.html>　置信度：高。
- **事件流 `PlayerStream` 字段全集**：`playlist`、`playing`、`completed`、`position`、`duration`、`volume`、`rate`、`pitch`、`buffering`、`buffer`、`playlistMode`、`shuffle`、`audioParams`、`videoParams`、`audioBitrate`、`audioDevice`、`audioDevices`、`track`、`tracks`、`width`、`height`、`subtitle`、`log`、`error`。README 明确说「`Player.stream.*` 提供 `Stream`，`Player.state.*` 提供瞬时值」。
  <https://pub.dev/documentation/media_kit/latest/media_kit/PlayerStream-class.html>、<https://github.com/media-kit/media-kit#handle-playback-events>　置信度：高。
- **playlist / next / previous 有原生支持**：`Playlist` 类型 + `player.next() / previous() / jump(index)` + `setPlaylistMode(PlaylistMode.loop/single/none)`。README 亦把 `Playlist support with next/previous/jump/shuffle` 列在特性清单。
  <https://github.com/media-kit/media-kit#open-a-media-or-playlist>　置信度：高。
- **`Media` 携带元数据与 HTTP 头**：`Media(uri, httpHeaders: Map<String,String>, extras: Map<String,dynamic>, start:, end:)`。README 专门有「Use HTTP headers」与「Use `extras` to store additional data with `Media`」两节（`extras` 的示例里放的正是 title/artist/album）。
  <https://pub.dev/documentation/media_kit/latest/media_kit/Media-class.html>、<https://github.com/media-kit/media-kit#use-http-headers>　置信度：高。
- 流里**没有**任何「当前曲目/标题/歌手」字段——曲目身份要靠 `playlist` + `playlist.index` 或 `Media.extras` 自行维护（Issue #913 用户也抱怨过「不知道在放哪首歌」）。

## 2.2 关键结论：media_kit 自己不提供后台播放与系统媒体控制

**是。media_kit 完全不提供，且官方文档/示例也没有覆盖这一点。**

证据（均为高置信度）：

1. **源码零实现（实测）**：解包 `media_kit-1.2.6.tar.gz`（包内只有 `lib/`、`assets/`、`example/`，**没有任何 android/ios/macos/windows 原生目录**），对全包 grep
   `AVAudioSession|UIBackgroundModes|MPNowPlayingInfoCenter|MPRemoteCommandCenter|MediaSession|SMTC|SystemMediaTransportControls|MPRIS|audio_service|audio_session`
   → **0 命中**。
   <https://pub.dev/api/archives/media_kit-1.2.6.tar.gz>（实测）
2. **README 零覆盖**：整份 README（2309 行）里 `background` 只出现 1 次，且是视频控件的 `backgroundColor: Color(0xaa000000)`；`audio_service`、`lock screen`、`now playing`、`media session`、`notification`、`UIBackgroundModes` 全部 0 命中。特性清单以 `Screenshot` 结尾，没有媒体控制项。
   <https://raw.githubusercontent.com/media-kit/media-kit/main/README.md>（实测 grep）
3. **维护者本人明确表态**：Issue #560 中 alexmercerind 说：*"Maybe an active foreground service is needed. package:audio_service can be hooked to package:media_kit on Android. **We do not have our own OS controls plugin at the moment**; which ideally should be easier to implement."*（2023-10-30）
   <https://github.com/media-kit/media-kit/issues/560#issuecomment-1785568310>
4. Issue #587（2023-11-13，至今 OPEN）标题为「Switching to a different apps pauses playback」，提问者直接问 *"Is there a flag or configuration setting that need to be set to enable 'background playback'?"*，维护者回答：*"I think you should use package:audio_service to avoid operating system from terminating your application in background... **We don't have a dedicated package to handle this right now. There will be a package:media_kit_os_controls at some point.**"*
   <https://github.com/media-kit/media-kit/issues/587>
5. Issue #913（2024-08-03，已关闭）中维护者再次说 *"I always wanted to have `media_kit_os_controls`... let's see."*
   <https://github.com/media-kit/media-kit/issues/913>
6. **`media_kit_os_controls` 至今不存在**（实测）：`https://pub.dev/api/packages/media_kit_os_controls` 返回 404；pub.dev 搜索 `media_kit` 也搜不到该包。即维护者承诺的官方 OS 控件包**截至 2026-09-10 未发布**。置信度：高。
7. 唯一沾边的是 `media_kit_video` 的 `VideoController` 有 `pauseUponEnteringBackgroundMode` / `resumeUponEnteringForegroundMode` 两个开关，作用是「进后台时暂停/回前台恢复」，**不是**系统媒体控制；维护者原话是「The videos were always meant to pause in background on Android & iOS」。而且该开关属于 `media_kit_video`，纯音频应用不引入它时并不生效。
   <https://github.com/media-kit/media-kit/issues/970#issuecomment-2371290018>

**社区组合方案（有权威旁证）**：media_kit 作者本人的音乐播放器 **Harmonoid** 的 `pubspec.yaml`（master，v0.3.34）同时依赖：
`audio_service: ^0.18.18`、`audio_session: ^0.2.3`、`media_kit`（git 引用）、以及桌面端自己维护的 `mpris_service`（Linux）与 `system_media_transport_controls`（本地 FFI 绑定 smtc-win32，Windows）。**注意它并不依赖 `just_audio`。**
<https://raw.githubusercontent.com/harmonoid/harmonoid/master/pubspec.yaml>　置信度：高（一手仓库文件）。

## 2.3 `audio_service` 与 media_kit 的兼容性、以及平台配置

- **版本**：`audio_service` **0.18.19**，发布于 **2026-06-29**，`sdk: ^3.6.0`、`flutter: >=3.27.0`，1331 likes / 140 分。
  <https://pub.dev/api/packages/audio_service>、<https://pub.dev/api/packages/audio_service/score>　置信度：高。
- **它对底层播放器没有绑定**。README 原文：*"`audio_service` is designed to let you implement the audio logic however you want, using whatever plugins you want. You can use your favourite audio plugins such as just_audio, flutter_tts, and others, within your audio handler."* 并在同一节提醒：*"this plugin will not work with other audio plugins that overlap in responsibility with this plugin (i.e. background audio, iOS control center, Android notifications, lock screen, headset buttons, etc.)"* —— **media_kit 恰好不碰这些职责（见 2.2），因此不构成冲突**。
  <https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md>　置信度：高。
- **没有官方示例，社区实践存在但 iOS 有坑**：
  - media_kit 官方仓库/包内**没有** media_kit + audio_service 的示例（实测 grep 包内全目录 0 命中）。
  - Issue #1227「Background audio playback (audio_service) on iOS not working.」（2025-07-22 提出，已被维护者关闭，无代码修复）：提问者说 Android 上 media_kit + audio_service 组合工作正常，iOS 上配置齐全仍不工作；跟帖解释 *"iOS being really strict about background audio and because it pauses for like a second when entering background iOS thinks your finished and wont let you continue"*。提问者还提到维护者曾提过的 `media_kit_os_controls`「I don't know if this actually happened」——确实没有发生。
    <https://github.com/media-kit/media-kit/issues/1227>
  - Issue #588「Audio stops playing when iOS devices goes to sleep」（2023-11-13，**至今 OPEN**，2 年多未修）：iOS 锁屏后音频停止，Android 正常。维护者只给了一个指向 #587 和 Xcode「Background Modes → Audio」勾选框的回复。
    <https://github.com/media-kit/media-kit/issues/588>
  - Issue #970 的后续跟帖（2025-05-07）也说：*"version 1.2.0 has background remote playback controller problem on iOS... open notification center and now playing works fine; minimize the app and maximize and now playing stops working."*
    <https://github.com/media-kit/media-kit/issues/970>
  - **结论：Android 上「media_kit + audio_service」是走得通的成熟路径；iOS 后台播放是已知薄弱环节，需要额外自研（见下）。**置信度：中高（多条互相印证的 Issue，但没有官方文档背书，也没有找到「iOS 上成功」的可验证样本）。
- **平台与原生实现（实测解包 `audio_service-0.18.19.tar.gz`）**：包内原生目录只有 `android/` 与 `darwin/`（iOS/macOS 共用），**没有 windows/linux**；pub.dev 平台标签为 `android, ios, macos, web`（web 由独立的 `audio_service_web` 提供）。
  <https://pub.dev/api/archives/audio_service-0.18.19.tar.gz>、<https://pub.dev/api/packages/audio_service/score>
  `darwin/audio_service/Sources/audio_service/AudioServicePlugin.m` 中命中 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` → **iOS 与 macOS 的「正在播放」与远程控制由它实现**。置信度：高。
- **README 明确列出的平台能力**（原文表格）：background audio ✅ Android/iOS/macOS/Web；notifications/control center ✅ 四个平台；lock screen controls ✅ Android/iOS/Web（**macOS 该格为空**）；Android Auto/CarPlay ✅ Android/iOS。
  <https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md>　置信度：高。
- **需要哪些平台配置（README 原文）**：
  - **Android**：`AndroidManifest.xml` 加 `WAKE_LOCK`、`FOREGROUND_SERVICE` 权限，target SDK 34 再加 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`；`<activity>` 改为继承 `AudioServiceActivity`（或自定义 Activity 继承它）；新增 `<service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback">`（含 `MediaBrowserService` intent-filter）；新增 `MediaButtonReceiver` receiver（`android.intent.action.MEDIA_BUTTON`）。Android 12+ 还有 `ForegroundServiceStartNotAllowedException` 的注意事项（用 `androidStopForegroundOnPause: false` 或引导用户关闭电池优化）。
  - **iOS**：`Info.plist` 加 `UIBackgroundModes: [audio]`；README 还提醒该模式只在「确实在播音频」时允许后台运行，空闲计时器会被系统杀进程，曲目间隙建议播静音轨。
  - **macOS**：把 `macos/Podfile` 的 `platform :osx` 改成 `'10.12.2'`（README 写「minimum supported macOS version is 10.12.2」）。
  - **Windows：README 完全未提及，也没有实现**（见 2.5）。
  - 置信度：高（均引自官方 README）。
- 近期 CHANGELOG：0.18.19 = Support AGP 9 / Android 构建迁移 `.kts`；0.18.18 = iOS `setPlaybackState` entitlement 修复、Android compile/target SDK 35、minSdk 19；0.18.17 = 支持 SwiftPM；0.18.16 = 支持 `MPNowPlayingInfoPropertyIsLiveStream`。
  <https://github.com/ryanheise/audio_service/blob/minor/audio_service/CHANGELOG.md>　置信度：高。

## 2.4 `audio_session` 的作用与配合方式

- **版本 0.2.4，发布 2026-06-29**，`sdk: ^3.6.0`、`flutter: >=3.27.0`，363 likes / 150 分，平台 **android / ios / macos / web（无 Windows）**，`is:plugin`。
  <https://pub.dev/api/packages/audio_session>、<https://pub.dev/api/packages/audio_session/score>
- **作用**（官方 README）：设置 **iOS 的 AVAudioSession 类别**（app 级）与 **Android 的 AudioAttributes**（每播放器），并管理**音频焦点、混音与 ducking**。
- **关键 API**：
  - `AudioSession.instance` → `configure(AudioSessionConfiguration.music())` / `.speech()` / 自定义（`avAudioSessionCategory`、`avAudioSessionMode`、`androidAudioAttributes`、`androidAudioFocusGainType`、`androidWillPauseWhenDucked` 等）；
  - `session.setActive(true)`（iOS 调 `AVAudioSession.setActive`，Android 调 `AudioManager.requestAudioFocus`）；
  - **耳机拔出**：`session.becomingNoisyEventStream.listen(...)`，官方注释就是「用户拔了耳机，我们应当暂停或降音量」；
  - **被其他 App 打断（来电/导航）**：`session.interruptionEventStream`（区分 `duck` / `pause` / `unknown`，并区分 begin/end）；
  - **设备增减**：`session.devicesChangedEventStream`；
  - **面向插件作者**：`configurationStream` 会把 Android 的 AudioAttributes 广播出去，播放器插件可订阅后应用到自己的音轨。
  <https://pub.dev/packages/audio_session>　置信度：高。
- **与 media_kit 的配合方式（需要自己接）**：
  - media_kit 自身**不订阅** `audio_session` 的任何流（见 2.2 的 grep 结果），`becomingNoisy` / `interruption` 都**不会自动暂停**。必须由 `audio_service` 的 `AudioHandler` 或你自己的胶水层订阅并调用 `player.pause()` / `player.play()`。
  - README 提醒：*"If your app uses a number of different audio plugins... it is possible that those plugins may internally overwrite each other's choice of these global system audio settings... it is recommended that you apply your own preferred configuration using audio_session after all other audio plugins have loaded."*
  - **一个具体的潜在冲突（实测 + 源码核对）**：libmpv 的 iOS 音频输出 `audio/out/ao_audiounit.m` 会主动执行
    `[instance setCategory:AVAudioSessionCategoryPlayback withOptions:options error:nil];`
    `[instance setMode:AVAudioSessionModeMoviePlayback error:nil];`
    并激活 session（<https://raw.githubusercontent.com/mpv-player/mpv/master/audio/out/ao_audiounit.m>）。
    也就是说**底层 libmpv 自己会把音频会话设成 playback + MoviePlayback**；按 audio_session 的建议，应在 MediaKit 初始化之后再 `configure(AudioSessionConfiguration.music())` 覆盖，否则 mode 可能停留在 MoviePlayback。
    置信度：中（mpv master 源码为高，但未核实 media_kit 打包的 libmpv-darwin-build 具体 revision 是否含这段代码）。

## 2.5 Windows / macOS 桌面端的系统媒体控制现状

- **macOS**：`audio_service` 自带 darwin 实现（`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`，实测源码命中），README 能力表列出 macOS 的 background audio / headset clicks / notifications·control center / album art ✅，**锁屏控制一栏为空**。→ **macOS 上直接用 `audio_service` 即可，不需要额外包。**置信度：高。
- **Windows**：`audio_service` 包内**没有 Windows 原生目录**，README 也未提 Windows → **官方不支持 Windows**。社区有三个候选（都不是 Ryan Heise 官方出品）：

| 包 | 版本 / 发布日 | likes/points | 平台 | 实现方式 | 维护者 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `audio_service_win` | **0.0.3 / 2026-03-29** | 3 / 140 | Windows | 自述为 audio_service 的 Windows **platform implementation**（SMTC） | HemantKArya（GitHub 5 stars） | README 称「作为依赖加入后 Windows 上会自动使用」；但 audio_service 的 federated 接口是否真正 endorsed 未经核实，见「未能核实」 |
| `smtc_windows` | **1.1.0 / 2025-08-18** | 13 / 140 | Windows | **Rust + flutter_rust_bridge**，自述「Windows 上的 audio_session 等价物」 | KRTirtho（frb_plugins monorepo，11 stars） | **要求本机装 rustup**；API：`SMTCWindows.initialize()`、`MusicMetadata`、`PlaybackTimeline`、`SMTCConfig`、`buttonPressStream`、`setPlaybackStatus`、`updateMetadata`、`dispose` |
| `flutter_media_session` | **3.0.4 / 2026-09-08** | 3 / 160 | Android, iOS, macOS, Windows, Web | 原生插件；Adapter 模式 | wyrindev（GitHub 1 star） | 文档里**直接给出 media_kit 的 copy-ready Adapter**（`MediaKitMediaSessionAdapter`），是本项目最省事的 Windows 方案，但包极新、生态信号极弱 |
| `audio_service_mpris` | 0.2.1 / 2026-03-15 | 12 / 160 | **仅 Linux** | D-Bus MPRIS | bdrazhzhov | **与本项目目标平台无关**（Hoomy 不做 Linux） |
| `notification_media_session` | 0.2.2 / 2026-09-01 | 1 / 110 | 未见平台标签 | — | Giant8east | 过新，不建议 |

来源：<https://pub.dev/api/packages/audio_service_win>、<https://pub.dev/api/packages/smtc_windows>、<https://pub.dev/api/packages/flutter_media_session>、<https://pub.dev/api/packages/audio_service_mpris>、<https://pub.dev/api/packages/notification_media_session>，以及 `smtc_windows` README <https://github.com/KRTirtho/frb_plugins/blob/main/packages/smtc_windows/README.md>、`flutter_media_session` README 与 `doc/usage.md`（含 media_kit adapter，第 276 行起）<https://raw.githubusercontent.com/wyrindev/flutter-media-session/main/doc/usage.md>。置信度：高（版本与平台事实）、中（成熟度评价）。

- **媒体键/硬件键**：`smtc_windows` 的 `buttonPressStream` 覆盖 play/pause/next/previous/stop/fastForward/rewind；`audio_service` 在 Android 走 `MediaButtonReceiver`，iOS/macOS 走 `MPRemoteCommandCenter`，所以三端的媒体键都有对应物。
- **旁证**：media_kit 作者自己的 Harmonoid 在 Windows 上不是用上面任何一个 pub 包，而是自己在仓库里维护 smtc-win32 的 FFI 绑定（`external/smtc-win32/bindings/system_media_transport_controls`）。说明**「自己写 FFI 绑定 WinRT SMTC」也是社区实际采用过的路径**，只是成本高。
  <https://raw.githubusercontent.com/harmonoid/harmonoid/master/pubspec.yaml>　置信度：高。

## 2.6 media_kit 的已知限制：带 query string 的 URL、HTTP header

- **`httpHeaders` 是官方支持能力**：`Media(uri, httpHeaders: {...})`，README 有专节；特性清单里明列 `✅ HTTP headers`。
  <https://github.com/media-kit/media-kit#use-http-headers>　置信度：高。
- **带 query string 的 URL：Dart 层不会改动它。**（实测）media_kit 用 `uri_parser: ^3.0.1` 的 `URIParser` 做归一化（`lib/src/models/media/media_native.dart` 的 `normalizeURI`），对 `URIType.network` 直接返回 `parser.uri!.toString()`。我用与 Subsonic 完全同形的 URL 实测：
  - `http://192.168.1.10:4533/rest/stream.view?id=123&u=user&t=abc123&s=salt` → **原样返回**；
  - `http://host/rest/stream.view?id=X&u=..&t=..&s=..` → 原样；
  - `http://host/path/file.flac?token=a+b&x=%2F`（`+` 与百分号编码）→ 原样；
  - `http://[fe80::1]:8080/song.flac?x=1`（IPv6 字面量）→ 原样。
  置信度：高（Dart 层实测）。**注意这只能证明 Dart 层不破坏 URL；libmpv/ffmpeg 层的最终行为未实测（本机没有 CocoaPods，无法构建 macOS 版 media_kit 做端到端播放验证）。**
- **未找到任何「query string 导致播放失败」的 Issue。**按标题/Body 搜索 `query string` / `querystring` 只命中 1 条无关 Issue（#1240 Query supported codecs/containers）。置信度：中（GitHub 未认证搜索有速率限制，覆盖面有限）。
- **真正需要警惕的相关已知问题（都是 OPEN）**：

| Issue | 状态 | 与本项目的相关性 |
| --- | --- | --- |
| [#1437](https://github.com/media-kit/media-kit/issues/1437) **Bundled Mbed TLS build has no TLS 1.3 client support (Android & iOS)**（2026-08-04） | OPEN | 报告者实测 media_kit 1.2.6 + `media_kit_libs_android_video` 1.3.8 / `media_kit_libs_ios_video` 1.1.4 内置的 Mbed TLS 缺 TLS 1.3 client，**对只接受 TLS 1.3 的服务器（如现代 CloudFront）握手失败**，报错是笼统的 `tls: A fatal alert message was received from the peer`。若用户把 Navidrome 暴露在只允许 TLS 1.3 的 HTTPS 上会踩到；局域网 HTTP 不受影响。 |
| [#1215](https://github.com/media-kit/media-kit/issues/1215) **[Bug] Initial seek() is ignored on authenticated network streams**（2025-07-04） | OPEN | 用 `httpHeaders` 带 Bearer token 的流上，`Media(start:)` 与 `player.seek()` 在打开后立刻调用都无效，总是从 0 开始（报告者只在 Android 复现）。→ 影响「续播上次进度」这一功能在有认证的流上的实现。 |
| [#897](https://github.com/media-kit/media-kit/issues/897) **How to set dynamic headers**（2024-07-08） | OPEN | 服务器要求每次请求（尤其 seek 触发的新请求）带**不同的 header**；media_kit 的 `httpHeaders` 在 `Media` 构造时固定，官方**没有**「按请求刷 header」的机制。Subsonic 的 `t=token&s=salt` 是**按曲目生成、放在 URL 里**的，所以本项目通常不受此限；但若 token 过期需要重新生成 URL，就要重新 `open()` 或自己重开播放。 |
| [#242](https://github.com/media-kit/media-kit/issues/242) **[Bug Report][Windows] HTTP error with specific source**（2023-06-17） | OPEN | 唯一一条「URL 带 `?sign=...` 却打不开」的记录，但根因经双方排查确认是 **ffmpeg/Mbed-TLS 的证书校验**（`tls: Creating security context failed (0x80090326)`），不是 query string 解析；维护者也只是猜测「seems like a parsing related issue to me」，未定论。 |
| [#510](https://github.com/media-kit/media-kit/issues/510) / [#783](https://github.com/media-kit/media-kit/issues/783) / [#1042](https://github.com/media-kit/media-kit/issues/1042) | 均已关闭 | **Web 平台不支持 HTTP headers**（1.2.0 CHANGELOG 有 `FIX: comment out unsupported headers on web`）。Hoomy 不做 Web，不受影响。 |

- 其他相关但非阻塞的 OPEN Issue：#970（进出后台行为）、#1289（Android 后台化崩溃 FlutterJNI）、#1378（Android 后台渲染帧堆积）、#1240（编解码支持查询）。

## 2.7 对 Hoomy 的落地建议（基于上述事实）

1. **播放器选 `media_kit` + `media_kit_libs_audio` 没问题**，playlist/next/previous/seek/position 流齐备，与 ADR-0002 的「统一播放器」一致。
2. **系统媒体控制与后台播放必须自己补，层级建议**：
   - 移动端（iOS + Android TV）：`audio_service 0.18.19` 作为 `AudioHandler` 外壳，内部持有 `media_kit` 的 `Player`；`audio_session 0.2.4` 负责音频会话/焦点/耳机拔出（`becomingNoisyEventStream` → `player.pause()`）与打断恢复（`interruptionEventStream`）。Android 还要按 README 改 Manifest（`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`AudioServiceActivity`、`AudioService`、`MediaButtonReceiver`）。Android TV 与手机同源，理论上同一套 Manifest/服务即可，但**未核实 TV 上的具体行为**。
   - macOS：同样用 `audio_service`（darwin 实现自带 Now Playing）。
   - Windows：`audio_service` 无实现。三选一：(a) `flutter_media_session 3.0.4` 且直接抄文档里的 media_kit Adapter（最省事，但包只 3 likes、1 star，需自行评估风险）；(b) `smtc_windows 1.1.0`（较成熟但引入 Rust 工具链，且要自己写桥接）；(c) `audio_service_win 0.0.3`（若它真能与 audio_service 联邦对接，可复用同一份 `AudioHandler`）。
3. **iOS 后台播放要有专门验收用例和 Plan B**：#588 已 OPEN 两年多；#1227 说明「照 audio_service 文档全配好」也未必在 iOS 上生效。建议在项目早期就在真机上验证「锁屏 / 切到别的 App / 锁屏超过 1 分钟」三条路径，并预留自写 `MPNowPlayingInfoCenter` 桥接的可能。
4. **URL 与认证**：Subsonic 的 `stream.view?id=..&u=..&t=..&s=..` 是 query string 认证，Dart 层已实测原样透传，**优先用这种方式**（而不是 `httpHeaders`），因为 (a) 无动态 header 支持，#897 是 OPEN；(b) #1215 表明带 header 的认证流上 `seek` 有 bug。**唯一要避免的是把服务器放在只支持 TLS 1.3 的 HTTPS 终端后面**（#1437），局域网 HTTP 或允许 TLS 1.2 的 HTTPS 都没问题——这也与 CONTEXT.md「仅接受标准证书校验」的约定相容。
5. **曲目身份/元数据**：media_kit 的事件流里没有 title/artist，需把「当前 playlist 索引 → 你的 Song 模型」这条链路自己维护好，再喂给 `audio_service` 的 `MediaItem`（title/artist/album/artUri/duration），锁屏与控制中心才会显示正确信息。

---

## 未能核实清单

1. **`chinese_pinyin` / `flutter_pinyin` 是否存在**：pub.dev API 返回 404，因此「pub.dev 上不存在」是确认的；但未能排除它们以其他形式（GitHub 未发布、其他 registry）存在。
2. **`audio_service_win` 与 `audio_service` 的联邦对接方式**：其 README 声称「加入依赖后 Windows 上自动生效」，但 `audio_service` 的 `pubspec.yaml` 中并未把 `audio_service_win` 列为 endorsed 实现，README 也没提。实际是否需要手动注册 platform instance **未核实**（未读其源码）。
3. **media_kit 在 Android TV（遥控器 D-pad 环境）上的后台/通知行为**：未找到任何 TV 相关文档或 Issue，未核实。`audio_service` 的 TV 行为同理。
4. **media_kit 对带 query string URL 的端到端（libmpv/ffmpeg 层）验证**：本机未安装 CocoaPods，无法构建 macOS 版做真实播放测试；只验证到 Dart 层的 `normalizeURI` 不破坏 URL。
5. **`pinyin` 3.3.0 在 Dart 3.13 上的长期兼容承诺**：实测可解析可运行，但版本已两年未发，未核实作者是否接受后续 Dart 版本破坏性变更。
6. **`lpinyin` 被 pub 判定 `is:dart3-compatible` 的内部规则**：仅确认了标签存在与实测可运行，未去查 pub 官方对 `<3.0.0` 上界的判定规则文档。
7. **各方案对最终 app 体积的实际增量**：只实测了源码/归档体积（lpinyin 416 KB / pinyin 4.08 MB），未实测 AOT 后 IPA/APK/EXE 的体积差。
8. **Windows ICU 的 `utrans_*` 转写符号是否真的在 `icu.dll` 导出**：只核实了 Windows 集成 ICU 且包含 i18n 组件（`icuin.dll`）、仅暴露 C API，未实际 `dumpbin` 验证导出表。
9. **`flutter_media_session` / `smtc_windows` 在 media_kit 上的实际可用性**：只核实了包的存在、版本、平台、文档与 API 形态，未做集成实测。

---

## 附：本次在本机做过的实测（可复现）

| 实测项 | 方法 | 结论 |
| --- | --- | --- |
| lpinyin / pinyin 在 Dart 3.13.2 下可解析 | 新建工程 `lpinyin: ^2.0.3` + `pinyin: ^3.3.0`，`dart pub get` | 成功，`+ lpinyin 2.0.3 + pinyin 3.3.0` |
| 首字母 API 语义 | `getShortPinyin` / `getFirstWordPinyin` 跑 10 个样例 | `五条人`→`wtr`/`wu`；`长城`→`cc`/`chang`；英文/数字/空格原样 |
| 多音字与姓氏 | 24 个姓名/词语两包对照 | 见 1.4 表 |
| 性能 | 首次调用 + 2000 次调用计时 | 19/40 ms 初始化；22/20 ms per 2000 |
| 词典规模 | 解包统计 `const List<String>` 条目 | 20,902 / 2,532 / 824 |
| `uri_parser` 对 query string 的处理 | 用 media_kit 依赖的 `uri_parser ^3.0.1` 跑 8 条 URL | 网络 URL 原样返回 |
| media_kit 包内是否含 OS 集成 | 解包 1.2.6 全目录 grep | 0 命中 |
| audio_service 原生平台 | 解包 0.18.19 看目录 + grep darwin | 只有 android/darwin；darwin 命中 MPNowPlayingInfoCenter / MPRemoteCommandCenter |
| intl 是否支持转写 | 解包 intl 0.20.3 grep `transliterat` | 0 命中 |
| Flutter 引擎是否带 ICU 数据 | `find ... -name "icudtl*.dat"` | 命中 darwin-x64 等多个 engine artifact |

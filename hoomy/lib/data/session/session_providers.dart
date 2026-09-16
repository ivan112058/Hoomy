import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../subsonic/models.dart';
import 'session.dart';

/// 当前会话：取数的唯一入口（ADR-0015 决策 1）。
///
/// **只由登录闸口注入**：闸口挂主界面时用嵌套作用域 override 出一个本地实例，
/// 因此主界面之内会话在类型上不可能为空，页面与播放层都不必再判空，也不存在
/// 「没有数据源」这种形态。
///
/// 默认实现直接抛错：在闸口之外读到它，就说明不变量被破坏了 —— 外壳的统一
/// 兜底据此给出可读原因与重试入口，而不是一片空白。抛 [StateError]（而不是
/// `Exception`）是刻意的：Riverpod 不会自动重试一个 `Error`。
final sessionProvider = Provider<Session>((ref) {
  throw StateError('会话未注入：主界面只能挂在登录闸口之下');
});

/// 取数失败**不自动重试**。
///
/// Riverpod 默认会按退避策略重试十次；那会让「失败」这一态一闪而过，用户既
/// 看不到原因也没有可点的重试入口，而且与改动前的行为不符。失败就停在失败态，
/// 重试由用户触发（[AsyncValueView] 的「重试」）。
Duration? noAutoRetry(int retryCount, Object error) => null;

/// 曲库里的全部歌曲。
///
/// 取数以异步值形态出现在接口上：页面只订阅它，取数身份、缓存与将来的失效
/// 都落在模块内部（ADR-0015 决策 4）。
///
/// `dependencies: [sessionProvider]` 不是可选项：会话是在**嵌套作用域**里注入的
/// （登录闸口），Riverpod 只有在依赖被静态声明时才知道该把这条取数放进哪个
/// 作用域；不声明就会挂在根作用域上，读到一个不存在的会话。后续每一条取数
/// provider 都要同样声明。
final allSongsProvider = FutureProvider<List<SubsonicSong>>(
  (ref) => ref.watch(sessionProvider).allSongs(),
  dependencies: [sessionProvider],
  retry: noAutoRetry,
);

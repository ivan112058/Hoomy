import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session.dart';
import '../session/session_providers.dart';
import 'star_target.dart';

/// 收藏写路径的落点（票据 12；全项目唯一的写操作）。
///
/// 界面负责**乐观更新与回滚**（先改本地、失败再改回去），本类负责另外两件事：
///
/// - 把 [StarTarget] 交给会话发出写请求；
/// - **同目标互斥**：同一目标已有请求在途时忽略后续点击，避免交错的重复请求
///   把最终状态写反（连点两下不应产生两次往返）。
///
/// 刻意**不做本地缓存**：收藏状态以服务端为准，界面每次取数都重新读服务端，
/// 因此不需要在客户端做过期与合并。
class StarStore {
  StarStore(this._session);

  /// 会话非空由作用域保证（ADR-0015 决策 2）：这里不存在「未登录」这一形态，
  /// 也就不必再为它造一个协议异常。
  final Session _session;

  final Set<StarTarget> _inFlight = {};

  /// 该目标是否有写请求在途。
  bool isSaving(StarTarget target) => _inFlight.contains(target);

  /// 收藏/取消收藏。
  ///
  /// 返回 `true` 表示请求已发出；`false` 表示同一目标已有请求在途，本次被忽略。
  /// 写失败时抛出 `SubsonicException`，由界面回滚并给出可读提示。
  Future<bool> setStarred({
    required StarTarget target,
    required bool starred,
  }) async {
    if (_inFlight.contains(target)) return false;
    _inFlight.add(target);
    try {
      await _session.setStarred(target, starred: starred);
      return true;
    } finally {
      _inFlight.remove(target);
    }
  }
}

/// 收藏写路径；绑在当前会话上。
///
/// 不持有可观察状态：乐观值由 `StarButton` 持有，互斥集合不需要驱动重建。
///
/// `dependencies: [sessionProvider]` 不是可选项：会话在嵌套作用域里注入，不声明
/// 依赖这条 provider 就会挂在根作用域上，读到一个不存在的会话（票据 02 的结论，
/// 票据 03 给同样依赖会话的非取数 provider 补上）。
final starStoreProvider = Provider<StarStore>(
  (ref) => StarStore(ref.watch(sessionProvider)),
  dependencies: [sessionProvider],
);

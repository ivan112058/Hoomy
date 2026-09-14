import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/repository_providers.dart';
import '../repositories/star_repository.dart';
import '../subsonic/subsonic_client.dart';
import 'star_target.dart';

/// 收藏写路径的落点（票据 12；全项目唯一的写操作）。
///
/// 界面负责**乐观更新与回滚**（先改本地、失败再改回去），本类负责另外两件事：
///
/// - 把 [StarTarget] 交给 [StarRepository] 发出写请求；
/// - **同目标互斥**：同一目标已有请求在途时忽略后续点击，避免交错的重复请求
///   把最终状态写反（连点两下不应产生两次往返）。
///
/// 刻意**不做本地缓存**：收藏状态以服务端为准，界面每次取数都重新读服务端，
/// 因此不需要在客户端做过期与合并。
class StarStore {
  StarStore(this._repository);

  final StarRepository? _repository;

  final Set<StarTarget> _inFlight = {};

  /// 该目标是否有写请求在途。
  bool isSaving(StarTarget target) => _inFlight.contains(target);

  /// 收藏/取消收藏。
  ///
  /// 返回 `true` 表示请求已发出；`false` 表示同一目标已有请求在途，本次被忽略。
  /// 写失败时抛 [SubsonicException]，由界面回滚并给出可读提示。
  Future<bool> setStarred({
    required StarTarget target,
    required bool starred,
  }) async {
    if (_inFlight.contains(target)) return false;
    final repository = _repository;
    if (repository == null) {
      throw const SubsonicException(-1, '尚未登录，无法收藏');
    }
    _inFlight.add(target);
    try {
      await repository.setStarred(target, starred: starred);
      return true;
    } finally {
      _inFlight.remove(target);
    }
  }
}

/// 收藏写路径；随当前登录用户派生。
///
/// 不持有可观察状态：乐观值由 [StarButton] 持有，互斥集合不需要驱动重建。
final starStoreProvider = Provider<StarStore>((ref) {
  return StarStore(ref.watch(starRepositoryProvider));
});

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Hoomy 的两种外壳形态（ADR-0013 决策 1）：手机形态与 TV 形态。
///
/// **平台即形态**：Android 只做 TV，其余（iOS）走手机外壳。不做机型探测、
/// 不看 `UiModeManager` —— 这是 ADR-0013 的前提，Android 上没有手机形态
/// 需要区分。
enum HoomyFormFactor { phone, tv }

/// 当前平台对应的形态。
///
/// 用 `dart:io` 的 [Platform] 判断真实宿主，而不是 `defaultTargetPlatform`：
/// 后者在 `flutter test` 里被强制成 Android（`FLUTTER_TEST` 分支），若拿它当
/// 依据，全部 widget 测试都会跑成 TV 外壳，手机形态反而失去覆盖。
///
/// 但 [debugDefaultTargetPlatformOverride] 优先：它是 Flutter 自己的「假装在
/// 某平台」开关，测试与预览用它就能让整条链（含 `Theme.platform`、默认快捷键
/// 映射）一起变成 TV 语义。
HoomyFormFactor get platformFormFactor {
  final override = debugDefaultTargetPlatformOverride;
  if (override != null) {
    return override == TargetPlatform.android
        ? HoomyFormFactor.tv
        : HoomyFormFactor.phone;
  }
  return Platform.isAndroid ? HoomyFormFactor.tv : HoomyFormFactor.phone;
}

/// 把形态注入部件树的入口：根部件（`HoomyApp`）按平台注入一次，页面与部件
/// 只读它，不各自去问平台。
///
/// 之所以用注入而不是让部件直接判断平台：widget 测试可以在部件级用例里显式
/// 指定形态（`formFactor: tv`），不必依赖宿主平台。
class HoomyFormFactorScope extends InheritedWidget {
  const HoomyFormFactorScope({
    super.key,
    required this.formFactor,
    required super.child,
  });

  final HoomyFormFactor formFactor;

  /// 取当前形态。
  ///
  /// 部件树里没有显式注入时退回 [platformFormFactor]：这条回退只服务于
  /// **独立挂载的部件**（部件级 widget 测试、单独预览某个页面），生产路径上
  /// 根部件总会注入一次。
  static HoomyFormFactor of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HoomyFormFactorScope>()
          ?.formFactor ??
      platformFormFactor;

  /// 是否处于 TV 形态。
  static bool isTv(BuildContext context) => of(context) == HoomyFormFactor.tv;

  @override
  bool updateShouldNotify(HoomyFormFactorScope oldWidget) =>
      formFactor != oldWidget.formFactor;
}

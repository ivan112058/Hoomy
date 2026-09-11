import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 屏幕常亮的接缝（ADR-0007）。
///
/// 常亮是平台能力，widget 测试里没有真实通道，所以开这一处注入点：生产用
/// [WakelockScreenAwake]，测试注入记录调用的假实现来验证「进入歌词态开启、
/// 离开歌词态或播放页清除」这条生命周期。
abstract interface class ScreenAwake {
  /// 开/关常亮。
  Future<void> setEnabled(bool enabled);

  /// 当前是否已开启常亮。
  bool get enabled;
}

/// 生产实现：`wakelock_plus`。
class WakelockScreenAwake implements ScreenAwake {
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // 平台没有常亮能力（或测试环境没有平台通道）时降级：屏幕照常熄灭，
      // 但不该因此影响歌词的呈现。
    }
  }
}

final screenAwakeProvider = Provider<ScreenAwake>(
  (ref) => WakelockScreenAwake(),
);

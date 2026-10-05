import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';

/// 定时关闭控制器（全局单例，[ChangeNotifier]）。
///
/// 「我的」页选择时长后开始按秒倒计时，首页左上角实时显示剩余时间；
/// 倒计时归零即退出应用（与返回键退出同款 [SystemNavigator.pop]）。
///
/// 只在本次运行期间有效，**不做持久化**：它是一次性的会话定时器，
/// 若持久化，重启应用后会莫名其妙地继续倒数并自动退出。
class SleepTimerController extends ChangeNotifier {
  SleepTimerController._();

  /// 全局单例。
  static final SleepTimerController instance = SleepTimerController._();

  /// 可选时长（分钟）：5~60 每 5 分钟一档，外加 90 分钟。
  static const List<int> presetMinutes = <int>[
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 90,
  ];

  /// 设置行的可选值：首项 null 代表「关闭」，其余为 [presetMinutes]。
  static const List<int?> options = <int?>[null, ...presetMinutes];

  int? _minutes;
  Duration _remaining = Duration.zero;
  Timer? _ticker;

  /// 当前选中的时长（分钟）；null 表示未开启。
  int? get minutes => _minutes;

  /// 是否正在倒计时。
  bool get active => _minutes != null;

  /// 剩余时间（每秒刷新）。
  Duration get remaining => _remaining;

  /// 设置定时：传 null 关闭，传分钟数则重新开始倒计时。
  void setMinutes(int? minutes) {
    if (minutes == null) {
      _stop();
      return;
    }
    _ticker?.cancel();
    _minutes = minutes;
    _remaining = Duration(minutes: minutes);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    final Duration next = _remaining - const Duration(seconds: 1);
    if (next > Duration.zero) {
      _remaining = next;
      notifyListeners();
      return;
    }
    // 到点：先复位状态，再退出应用。
    _ticker?.cancel();
    _ticker = null;
    _minutes = null;
    _remaining = Duration.zero;
    notifyListeners();
    _shutdown();
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _minutes = null;
    _remaining = Duration.zero;
    notifyListeners();
  }

  /// 定时到点：退出应用。
  Future<void> _shutdown() async {
    Injection.get<LogService>().info('[SleepTimer] 定时关闭生效，退出应用');
    // 复用返回键退出的方式：结束 Activity（与系统返回最终效果一致）。
    await SystemNavigator.pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
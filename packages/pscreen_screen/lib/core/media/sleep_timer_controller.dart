import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/app/app_log.dart';

/// 定时关闭控制器（全局单例，[ChangeNotifier]）。
///
/// 「我的」页选择时长后开始按秒倒计时，首页左上角实时显示剩余时间；
/// 倒计时归零默认退出应用（与返回键退出同款 [SystemNavigator.pop]）；
/// 宿主可通过 [onExpire] 覆盖为「关闭直播回主页」等动作（中控屏）。
///
/// 只在本次运行期间有效，**不做持久化**：它是一次性的会话定时器，
/// 若持久化，重启应用后会莫名其妙地继续倒数并自动退出。
class SleepTimerController extends ChangeNotifier {
  SleepTimerController._();

  /// 全局单例。
  static final SleepTimerController instance = SleepTimerController._();

  /// 可选时长（分钟）：5~60 每 5 分钟一档，外加 90 分钟。
  static const List<int> presetMinutes = <int>[
    5,
    10,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
    90,
  ];

  /// 设置行的可选值：首项 null 代表「关闭」，其余为 [presetMinutes]。
  static const List<int?> options = <int?>[null, ...presetMinutes];

  int? _minutes;
  Duration _remaining = Duration.zero;
  Timer? _ticker;

  /// 到点后的动作；为空时默认退出应用（电视端）。
  ///
  /// 中控屏注入「关闭直播回到主页」：它的定时关闭只是关掉屏幕上的内容，
  /// 不能把整台中控台退出。
  VoidCallback? onExpire;

  /// 当前选中的时长（分钟）；null 表示未开启。
  int? get minutes => _minutes;

  /// 是否正在倒计时。
  bool get active => _minutes != null;

  /// 剩余时间（每秒刷新）。
  Duration get remaining => _remaining;

  /// 剩余时间的 `mm:ss` 文案（≥1 小时为 `H:mm:ss`）。
  String get remainingLabel {
    final String mm = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    if (_remaining.inHours > 0) return '${_remaining.inHours}:$mm:$ss';
    return '$mm:$ss';
  }

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
    // 到点：先复位状态，再执行到点动作（宿主未注入时退出应用）。
    _ticker?.cancel();
    _ticker = null;
    _minutes = null;
    _remaining = Duration.zero;
    notifyListeners();
    final VoidCallback? expire = onExpire;
    if (expire == null) {
      _shutdown();
    } else {
      Log.i('[SleepTimer] 定时关闭生效，执行宿主自定义动作');
      expire();
    }
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _minutes = null;
    _remaining = Duration.zero;
    notifyListeners();
  }

  /// 定时到点的默认动作：退出应用（电视端；宿主未注入 [onExpire] 时）。
  Future<void> _shutdown() async {
    Log.i('[SleepTimer] 定时关闭生效，退出应用');
    // 复用返回键退出的方式：结束 Activity（与系统返回最终效果一致）。
    await SystemNavigator.pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

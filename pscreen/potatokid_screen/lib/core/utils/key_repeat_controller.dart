import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 遥控器按键长按快速重复控制器（全局单例）。
///
/// 解决 TV 盒子上长按方向键只能一步步移动的问题：
/// 第一次按下立即执行一次，短暂延迟后进入快速重复模式，
/// 抬起按键即停止。
///
/// 用法：
/// ```dart
/// // KeyDown 时调用：
/// KeyRepeatController.instance.keyDown(
///   LogicalKeyboardKey.arrowDown,
///   () => myAction(),
/// );
///
/// // KeyUp 时调用：
/// KeyRepeatController.instance.keyUp(LogicalKeyboardKey.arrowDown);
/// ```
///
/// **为什么不能只依赖 KeyUp**：只要漏掉一次 KeyUp（按着键切窗口/切后台，
/// 或上层把事件丢了），该键的计时器就会永远留着。而 [keyDown] 原本遇到
/// 「已有计时器」会直接忽略 —— 于是这个键之后**再也按不动**，同时那个
/// 80ms 周期计时器还在后台不停空转，不重启永远恢复不了。
/// 所以这里加了三道自愈，见 [keyDown] / [_startRepeating] /
/// [didChangeAppLifecycleState]。
class KeyRepeatController with WidgetsBindingObserver {
  KeyRepeatController._();

  static final KeyRepeatController instance = KeyRepeatController._();

  /// 首次按下后多久进入快速重复（毫秒）。
  static const int _initialDelayMs = 400;

  /// 快速重复的间隔（毫秒），值越小滚动越快。
  static const int _repeatIntervalMs = 80;

  /// 每个按键对应的重复计时器。
  final Map<LogicalKeyboardKey, Timer> _timers = <LogicalKeyboardKey, Timer>{};

  /// 是否已挂上生命周期观察者。
  bool _observing = false;

  /// 某个按键是否正处于长按快速重复中。
  bool isRepeating(LogicalKeyboardKey key) => _timers.containsKey(key);

  /// 按下按键：首次立即执行 [action]，并启动快速重复计时器。
  ///
  /// Flutter 3.13 起，真机上的「长按重复」是 [KeyRepeatEvent]（且不会走到
  /// 这里 —— 调用方只处理 [KeyDownEvent]），所以重复收到同一个键的
  /// [KeyDownEvent] 只可能是**真的又按了一次**。此时重建计时器而不是忽略：
  /// 上一次的 KeyUp 若丢了，这一次按下就能把残留状态清掉、恢复可用。
  void keyDown(LogicalKeyboardKey key, VoidCallback action) {
    _ensureObserving();
    // 自愈 1：已有残留计时器时当作全新按下处理（先清掉再重建）。
    _timers.remove(key)?.cancel();

    // 首次按下立即执行一次。
    action();

    // 延迟后进入快速重复。
    _timers[key] = Timer(
      const Duration(milliseconds: _initialDelayMs),
      () => _startRepeating(key, action),
    );
  }

  /// 抬起按键：停止该按键的重复计时器。
  void keyUp(LogicalKeyboardKey key) {
    final Timer? timer = _timers.remove(key);
    timer?.cancel();
  }

  /// 停止所有按键的重复（失去焦点 / 切后台时调用）。
  void cancelAll() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _startRepeating(LogicalKeyboardKey key, VoidCallback action) {
    _timers[key]?.cancel();
    _timers[key] = Timer.periodic(
      const Duration(milliseconds: _repeatIntervalMs),
      (_) {
        // 自愈 3：每跳一次都核对框架的按键状态。框架已经不认为这个键按下了
        // （说明我们漏掉了 KeyUp），就立刻停掉 —— 既止住后台空转，也避免
        // 这个键因为「计时器一直存在」而永远按不动。
        if (!HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
          keyUp(key);
          return;
        }
        action();
      },
    );
  }

  /// 自愈 2：失焦 / 切后台是「丢失 KeyUp」的典型场景，一律清空计时器兜底。
  ///
  /// 桌面端切换窗口、移动端切到后台都会走到这里。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancelAll();
  }

  /// 首次使用时挂上生命周期观察者；单例存活到进程结束，不需要注销。
  void _ensureObserving() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }
}
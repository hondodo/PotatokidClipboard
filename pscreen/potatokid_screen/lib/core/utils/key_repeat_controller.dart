import 'dart:async';

import 'package:flutter/services.dart';

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
class KeyRepeatController {
  KeyRepeatController._();

  static final KeyRepeatController instance = KeyRepeatController._();

  /// 首次按下后多久进入快速重复（毫秒）。
  static const int _initialDelayMs = 400;

  /// 快速重复的间隔（毫秒），值越小滚动越快。
  static const int _repeatIntervalMs = 80;

  /// 每个按键对应的重复计时器。
  final Map<LogicalKeyboardKey, Timer> _timers = <LogicalKeyboardKey, Timer>{};

  /// 某个按键是否正处于长按快速重复中。
  bool isRepeating(LogicalKeyboardKey key) => _timers.containsKey(key);

  /// 按下按键：首次立即执行 [action]，并启动快速重复计时器。
  ///
  /// 如果该键已有计时器（说明是系统 repeat 事件），直接忽略，
  /// 由我们自己的 Timer 控制重复节奏。
  void keyDown(LogicalKeyboardKey key, VoidCallback action) {
    if (_timers.containsKey(key)) return; // 已在重复中，忽略系统 repeat

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

  /// 停止所有按键的重复（例如失去焦点时调用）。
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
      (_) => action(),
    );
  }
}

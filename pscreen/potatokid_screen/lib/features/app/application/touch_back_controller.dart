import 'package:flutter/widgets.dart';

/// 触屏「返回」桥接。
///
/// 触屏设备（`phone` flavor）没有实体遥控器的返回键，而遥控端的返回是**逐层**的：
/// 行内编辑 → 正文焦点 → 非首页回直播 → 首页才退出。触屏若自己另写一套，
/// 很容易与遥控行为分叉，所以这里只做接线：把 [MainApp] 的返回逻辑暴露出来，
/// 由非直播页的可点返回按钮复用，触屏与遥控走同一条链。
///
/// 生命周期：`MainApp` 在 `build` 里 attach（常驻，幂等）；app 生命周期内不会失效。
class TouchBackController {
  TouchBackController._();

  static final TouchBackController instance = TouchBackController._();

  bool Function(BuildContext context)? _handler;

  /// 接线（由 MainApp 调用）。
  void attach(bool Function(BuildContext context) handler) {
    _handler = handler;
  }

  /// 断开接线。
  void detach() {
    _handler = null;
  }

  /// 触发一次「返回」。未接线时返回 false（调用方应忽略，不做退出等破坏性动作）。
  bool requestBack(BuildContext context) => _handler?.call(context) ?? false;
}

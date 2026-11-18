import 'dart:async';

import 'package:flutter/material.dart';

/// 直播全屏「触屏手势层」——平行输入适配器。
///
/// 设计约束（见 docs/tv-touch-control-plan.md，遥控零影响为硬底线）：
/// - 只把 pointer 手势翻译成对现有控制器单例的调用，**绝不触碰任何 KeyEvent 链路**；
///   遥控经 `MainApp._handleLogical` 分发，与本层完全隔离，行为不受任何影响。
/// - 业务动作全部由回调给出，本层不持有频道/播放状态，避免与遥控产生第二套真值源。
/// - [enabled] 由宿主按「交互层 + 覆盖层」计算；[shouldAccept] 在每次按下时二次确认，
///   覆盖层 widget 自身的 opaque 命中 + 这两道门控共同保证不穿透误操作。
///
/// 手势约定（2026-11-17 定稿；2026-11-18 调整）：
/// - 单击：切换频道信息 OSD；
/// - 长按（500ms）：呼出频道列表；
/// - 四向滑动（上/下/左/右）：**2026-11-18 起宿主已关闭换台/换源**——触屏下滑是
///   查看系统栏的系统手势，误触会切频道，严重影响使用。直播间接线处四个
///   onSwipe* 回调统一置 `_touchNoop`。本层仍保留滑动识别能力（识别为 swipe
///   后不触发 tap），只是宿主不再绑定业务动作；单击、长按不受影响。
class TouchGestureLayer extends StatefulWidget {
  const TouchGestureLayer({
    super.key,
    required this.enabled,
    required this.shouldAccept,
    required this.onTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onLongPress,
  });

  /// 当前是否允许触屏手势（交互层 + 覆盖层门控的即时结果）。
  final bool enabled;

  /// 每次 pointer down 时的二次确认，防止门控状态在两次 build 之间变化。
  final bool Function() shouldAccept;

  final VoidCallback onTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onLongPress;

  @override
  State<TouchGestureLayer> createState() => _TouchGestureLayerState();
}

class _TouchGestureLayerState extends State<TouchGestureLayer> {
  /// 判定「滑动 vs 点击」的最小位移（逻辑像素，视口 FittedBox 逆变换后坐标）。
  static const double _touchSlop = 24;

  /// 主轴优势比：|dy| >= |dx| * ratio 判为垂直滑动，反之水平。
  static const double _axisRatio = 1.4;

  /// 长按触发时长。
  static const Duration _longPressDelay = Duration(milliseconds: 500);

  /// 连续滑动节流：避免一次长距离拖动/抖动连切多台。
  static const Duration _swipeThrottle = Duration(milliseconds: 250);

  Timer? _longPressTimer;
  Offset? _down;
  bool _moved = false;
  bool _longPressFired = false;
  DateTime? _lastSwipe;

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _reset() {
    _cancelLongPress();
    _down = null;
    _moved = false;
    _longPressFired = false;
  }

  Offset? _deltaOf(PointerEvent e) {
    final Offset? down = _down;
    if (down == null) return null;
    return e.localPosition - down;
  }

  void _onDown(PointerDownEvent e) {
    if (!widget.shouldAccept()) return;
    // 只接受主键（触屏 / 鼠标左键）；忽略右键等次级按键。
    if (e.buttons == 0 || e.buttons & 1 == 0) return;
    _down = e.localPosition;
    _moved = false;
    _longPressFired = false;
    _cancelLongPress();
    _longPressTimer = Timer(_longPressDelay, () {
      if (!mounted || _moved || _down == null) return;
      _longPressFired = true;
      widget.onLongPress();
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (_down == null) return;
    final Offset? d = _deltaOf(e);
    if (d == null) return;
    if (!_moved && (d.dx.abs() > _touchSlop || d.dy.abs() > _touchSlop)) {
      _moved = true;
      // 一旦判定为滑动，取消长按，避免滑动结束又误触发呼出列表。
      _cancelLongPress();
    }
  }

  void _onUp(PointerUpEvent e) {
    final bool hadDown = _down != null;
    final bool fired = _longPressFired;
    final bool moved = _moved;
    final Offset? d = _deltaOf(e);
    _reset();
    if (!hadDown || fired || d == null) return;

    final double dx = d.dx;
    final double dy = d.dy;
    if (!moved || (dx.abs() < _touchSlop && dy.abs() < _touchSlop)) {
      widget.onTap();
      return;
    }

    // 滑动节流：节流窗口内的后续滑动丢弃。
    final DateTime now = DateTime.now();
    final DateTime? last = _lastSwipe;
    if (last != null && now.difference(last) < _swipeThrottle) return;

    if (dy.abs() >= dx.abs() * _axisRatio) {
      _lastSwipe = now;
      if (dy < 0) {
        widget.onSwipeUp();
      } else {
        widget.onSwipeDown();
      }
    } else if (dx.abs() >= dy.abs() * _axisRatio) {
      _lastSwipe = now;
      if (dx < 0) {
        widget.onSwipeLeft();
      } else {
        widget.onSwipeRight();
      }
    }
    // 斜向且两轴都不占优势（接近 45°）→ 不动作，避免误触。
  }

  void _onCancel(PointerCancelEvent e) => _reset();

  @override
  void dispose() {
    _cancelLongPress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Listener(
        // translucent：参与命中但不吞掉下层（频道条在更高层，showChannels 时
        // 本层被 IgnorePointer 禁用，频道条 onTap 正常生效）。
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: const SizedBox.expand(),
      ),
    );
  }
}

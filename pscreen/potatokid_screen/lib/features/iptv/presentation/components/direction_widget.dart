import 'package:flutter/material.dart';

/// 遥控方向键提示：以「圆形底盘 + 四向箭头 + 中心 OK」的图形表示遥控器方向键。
///
/// 某个方向传 true 即为「热键」——该键会被主色点亮并循环闪烁，用于提示当前
/// 可操作的方向（如主页提示「按下 ◀ ▶ 更换播放源」）。全为 false 时不启动
/// 动画，避免无谓刷新。
///
/// 尺寸说明：控件为正方形，边长由 [size] 决定。由于要同时容纳 5 个按键，
/// [size] 小于约 32 时图标会失真——它此时主要作为「方向键」的形状符号，
/// 而不是可辨认的图标。需要清晰可读时把 [size] 调到 44 以上。
class DirectionWidget extends StatefulWidget {
  const DirectionWidget({
    super.key,
    this.hotLeft = false,
    this.hotRight = false,
    this.hotUp = false,
    this.hotDown = false,
    this.hotOk = false,
    this.size = 36,
  });

  final bool hotLeft;
  final bool hotRight;
  final bool hotUp;
  final bool hotDown;
  final bool hotOk;

  /// 控件边长（正方形）。
  final double size;

  @override
  State<DirectionWidget> createState() => _DirectionWidgetState();
}

class _DirectionWidgetState extends State<DirectionWidget> with SingleTickerProviderStateMixin {
  /// 一个控制器驱动所有热键的闪烁，避免每个方向各起一个动画。
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  /// 热键闪烁的透明度：0.55 ↔ 1.0，够醒目又不刺眼。
  late final Animation<double> _hotOpacity = Tween<double>(
    begin: 0.55,
    end: 1,
  ).animate(CurvedAnimation(parent: _blink, curve: Curves.easeInOut));

  /// 是否有任一方向需要闪烁。
  bool get _hasHot => widget.hotLeft || widget.hotRight || widget.hotUp || widget.hotDown || widget.hotOk;

  @override
  void initState() {
    super.initState();
    if (_hasHot) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(DirectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在「有/无热键」切换时启停，避免每次 build 都重启动画。
    if (_hasHot) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else if (_blink.isAnimating) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _hotOpacity,
        builder: (BuildContext context, Widget? child) {
          return DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.5)),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _cap(scheme, alignment: Alignment.topCenter, icon: Icons.keyboard_arrow_up, hot: widget.hotUp),
                _cap(scheme, alignment: Alignment.bottomCenter, icon: Icons.keyboard_arrow_down, hot: widget.hotDown),
                _cap(scheme, alignment: Alignment.centerLeft, icon: Icons.keyboard_arrow_left, hot: widget.hotLeft),
                _cap(scheme, alignment: Alignment.centerRight, icon: Icons.keyboard_arrow_right, hot: widget.hotRight),
                Align(
                  alignment: Alignment.center,
                  child: _okKey(scheme, hot: widget.hotOk),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 方向键帽：贴着底盘边缘，使键心距圆心约 0.36×边长。
  ///
  /// 键帽直径取 0.28×边长时，键帽恰好完整落在底盘内且不与中心键重叠。
  Widget _cap(ColorScheme scheme, {required Alignment alignment, required IconData icon, required bool hot}) {
    final double d = widget.size * 0.28;
    return Align(
      alignment: alignment,
      child: Opacity(
        opacity: hot ? _hotOpacity.value : 1,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hot ? Colors.amber.shade200 : Colors.white.withValues(alpha: 0.5),
            boxShadow: hot
                ? <BoxShadow>[BoxShadow(color: scheme.primary.withValues(alpha: 0.55), blurRadius: 8, spreadRadius: 1)]
                : null,
          ),
          child: Icon(icon, size: d * 0.68, color: hot ? Colors.black : Colors.black87),
        ),
      ),
    );
  }

  /// 中心 OK 键。
  Widget _okKey(ColorScheme scheme, {required bool hot}) {
    final double d = widget.size * 0.40;
    return Opacity(
      opacity: hot ? _hotOpacity.value : 1,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hot ? Colors.amber.shade100 : Colors.white.withValues(alpha: 0.5),
          boxShadow: hot
              ? <BoxShadow>[BoxShadow(color: scheme.primary.withValues(alpha: 0.55), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
        child: Text(
          'OK',
          style: TextStyle(
            color: hot ? Colors.black : Colors.black87,
            fontSize: d * 0.42,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

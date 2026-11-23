import 'package:flutter/material.dart';

/// 渐变轨道滑块：左侧填充渐变、右侧留灰色底轨，拇指为白色圆角条。
///
/// 用于亮度 / 色温这类「视觉上需要看出档位」的连续量。拖动过程只回调
/// [onChanged]（本地即时反馈），松手才通过 [onChangeEnd] 下发指令，
/// 避免一次拖动向 HA 连发几十条服务调用。
class GradientSlider extends StatefulWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.colors,
    this.min = 0,
    this.max = 100,
    this.onChanged,
    this.onChangeEnd,
    this.onChangeEndAsync,
    this.height = 28,
    this.thumbWidth = 12,
    this.thumbHeight = 42,
    this.enabled = true,
    this.trackColor,
    this.offline = false,
    this.thumbColor,
    this.thumbBorderColor,
  }) : assert(colors.length >= 2, '渐变至少需要两种颜色');

  final double value;
  final List<Color> colors;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// 松手后的异步提交结果。返回 true 表示上层已接受并把权威值更新到目标值；
  /// 返回 false（断线 / 请求失败 / 被白名单拦截）时本地预览自动回滚到 [value]。
  ///
  /// 与 [onChangeEnd] 二选一：传了它就不会再调 [onChangeEnd]，避免重复下发。
  final Future<bool> Function(double)? onChangeEndAsync;
  final double height;
  final double thumbWidth;
  final double thumbHeight;
  final bool enabled;

  /// 未填充部分的底轨颜色；null 时退回 surfaceContainerHighest。
  ///
  /// 触屏没有 hover，若底轨与卡片背景同色会导致滑条「看不见」。
  /// 常显场景（如首页灯卡）应传与背景对比明显的颜色（如 outlineVariant）。
  final Color? trackColor;

  /// 离线态：用暗灰渐变 + 暗色拇指，仍常显可辨，但一眼能看出设备离线。
  /// 与 enabled=false（禁用拖动）不同，这里只换配色，不隐藏滑条。
  final bool offline;

  /// 拇指填充色 / 描边色；不传时按在线（白）/离线（暗灰）默认。
  final Color? thumbColor;
  final Color? thumbBorderColor;

  @override
  State<GradientSlider> createState() => _GradientSliderState();
}

class _GradientSliderState extends State<GradientSlider> {
  late double _value = _normalized(widget.value);
  bool _dragging = false;

  double _normalized(double raw) =>
      raw.clamp(widget.min, widget.max).toDouble();

  @override
  void didUpdateWidget(GradientSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 拖动中不覆盖本地值，避免 HA 推送把手指下的滑块拽回去
    if (!_dragging && oldWidget.value != widget.value) {
      _value = _normalized(widget.value);
    }
  }

  void _updateFromDx(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    final double fraction = (dx / width).clamp(0.0, 1.0);
    final double value = widget.min + fraction * (widget.max - widget.min);
    setState(() => _value = value);
    widget.onChanged?.call(value);
  }

  void _finish() {
    if (!_dragging) return;
    _dragging = false;
    final double committed = _value;
    final Future<bool> Function(double)? asyncHandler = widget.onChangeEndAsync;
    if (asyncHandler == null) {
      widget.onChangeEnd?.call(committed);
      return;
    }
    asyncHandler(committed).then((bool accepted) {
      if (!mounted || accepted) return;
      // 指令没真正生效：把乐观预览还原成设备权威值，避免重连后
      // 文字已显示实际风速、滑条却仍停在用户上次拖动的位置。
      setState(() => _value = _normalized(widget.value));
    }, onError: (Object _) {
      if (!mounted) return;
      setState(() => _value = _normalized(widget.value));
    });
  }

  void _cancelDrag() {
    if (!_dragging) return;
    _dragging = false;
    // 手势被系统打断（没有松手提交），本地预览必须立即回到权威值。
    setState(() => _value = _normalized(widget.value));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double fraction =
        ((_value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    final double radius = widget.height / 2;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double thumbLeft = (width * fraction - widget.thumbWidth / 2)
            .clamp(0.0, width - widget.thumbWidth);
        // 始终显示拇指，即便在 0% / 离线时也一样，明确标识「这是一条可拖动的滑条」，
        // 触屏设备没有 hover，常显是让用户看出它可滑的唯一方式。
        final bool showThumb = true;
        // 在线=调用方传入的彩色渐变；离线=暗灰渐变，配色本身区分在线状态，
        // 不再靠整体透明度压暗（压暗会让触屏用户误以为滑条不存在）。
        final List<Color> fillColors = widget.offline
            ? <Color>[
                theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                theme.colorScheme.outlineVariant,
              ]
            : widget.colors;
        final Color resolvedTrack = widget.offline
            ? theme.colorScheme.surfaceContainerHighest
            : (widget.trackColor ?? theme.colorScheme.surfaceContainerHighest);
        final Color resolvedThumb =
            widget.thumbColor ?? (widget.offline ? theme.colorScheme.outline : Colors.white);
        final Color resolvedThumbBorder = widget.thumbBorderColor ??
            (widget.offline ? theme.colorScheme.outlineVariant : const Color(0xFFCFCFCF));
        return Opacity(
          opacity: 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) {
              _dragging = true;
              _updateFromDx(d.localPosition.dx, width);
            },
            onTapUp: (TapUpDetails _) => _finish(),
            onTapCancel: _cancelDrag,
            onHorizontalDragStart: (DragStartDetails d) {
              _dragging = true;
              _updateFromDx(d.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _updateFromDx(d.localPosition.dx, width),
            onHorizontalDragEnd: (DragEndDetails _) => _finish(),
            onHorizontalDragCancel: _cancelDrag,
            child: SizedBox(
              height: widget.thumbHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  Positioned(
                    left: 0,
                    right: 0,
                    child: Container(
                      height: widget.height,
                      decoration: BoxDecoration(
                        color: resolvedTrack,
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: (widget.thumbHeight - widget.height) / 2,
                    child: Container(
                      width: width * fraction,
                      height: widget.height,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: fillColors),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                  if (showThumb)
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      child: Container(
                        width: widget.thumbWidth,
                        height: widget.thumbHeight,
                        decoration: BoxDecoration(
                          color: resolvedThumb,
                          borderRadius:
                              BorderRadius.circular(widget.thumbWidth),
                          border: Border.all(
                            color: resolvedThumbBorder,
                            width: 1.5,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

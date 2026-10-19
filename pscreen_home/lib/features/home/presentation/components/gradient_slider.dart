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
    this.height = 14,
    this.thumbWidth = 6,
    this.thumbHeight = 22,
    this.enabled = true,
    this.trackColor,
  }) : assert(colors.length >= 2, '渐变至少需要两种颜色');

  final double value;
  final List<Color> colors;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;
  final double thumbWidth;
  final double thumbHeight;
  final bool enabled;

  /// 未填充部分的底轨颜色；null 时退回 surfaceContainerHighest。
  ///
  /// 触屏没有 hover，若底轨与卡片背景同色会导致滑条「看不见」。
  /// 常显场景（如首页灯卡）应传与背景对比明显的颜色（如 outlineVariant）。
  final Color? trackColor;

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
    widget.onChangeEnd?.call(_value);
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
        // 亮度从 0 起时，关闭状态不画拇指，避免卡片左下角出现一条白线
        final bool showThumb = !(fraction == 0 && widget.min == 0);
        return Opacity(
          opacity: widget.enabled ? 1 : 0.45,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) {
              _dragging = true;
              _updateFromDx(d.localPosition.dx, width);
            },
            onTapUp: (TapUpDetails _) => _finish(),
            onTapCancel: () => _dragging = false,
            onHorizontalDragStart: (DragStartDetails d) {
              _dragging = true;
              _updateFromDx(d.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _updateFromDx(d.localPosition.dx, width),
            onHorizontalDragEnd: (DragEndDetails _) => _finish(),
            onHorizontalDragCancel: () => _dragging = false,
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
                        color: widget.trackColor ??
                            theme.colorScheme.surfaceContainerHighest,
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
                        gradient: LinearGradient(colors: widget.colors),
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
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(widget.thumbWidth),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
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

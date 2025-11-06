import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/gen/assets.gen.dart';

class LoadingWidget extends StatefulWidget {
  const LoadingWidget({
    super.key,
    this.text = '',
  });

  final String text;

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget>
    with TickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        double textWidth = StringUtil.getTextWidth(
                widget.text,
                const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                )) +
            40;
        const double minWidth = 80.0; // 您可以根据实际需求设置最小值
        double containerWidth =
            widget.text.isNotEmpty ? math.max(textWidth, minWidth) : 80.0;

        return Container(
          width: containerWidth,
          height: widget.text != '' ? 100 : 80,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: LoadingAnimatedWidget(
                    controller: _controller,
                  ),
                ),
                Visibility(
                  visible: widget.text != '',
                  child: Container(
                    margin: const EdgeInsets.only(top: 15),
                    child: Text(
                      widget.text,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class LoadingAnimatedWidget extends AnimatedWidget {
  const LoadingAnimatedWidget(
      {super.key,
      required AnimationController controller,
      this.width = 56.0,
      this.height = 56.0})
      : super(listenable: controller);

  Animation<double> get _progress => listenable as Animation<double>;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: (_progress.value * 8).toInt() / 8.0 * 2.0 * math.pi,
      child: Assets.images.common.commonLoading
          .image(width: width, height: height),
    );
  }
}

class LoadingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var width = size.width;
    var height = size.height;
    var center = Offset(width / 2, height / 2);
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = ui.Gradient.sweep(center, [Colors.white, Colors.transparent]);
    canvas.drawCircle(center, center.dx, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StringUtil {
  static double getTextWidth(String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter.size.width;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 流动彩色背景：缓慢旋转/流动的多色渐变 + 20% 黑色蒙层。
/// 三屏（完整 / 仅时间 / 转盘）共用。
class FlowingGradientBackground extends StatefulWidget {
  const FlowingGradientBackground({super.key});

  @override
  State<FlowingGradientBackground> createState() =>
      _FlowingGradientBackgroundState();
}

class _FlowingGradientBackgroundState extends State<FlowingGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              painter: _FlowingPainter(_controller.value),
              size: Size.infinite,
            ),
            // 20% 黑蒙层，压暗背景以保证白色文字/表盘对比度。
            const ColoredBox(color: Color(0x33000000)),
          ],
        );
      },
    );
  }
}

class _FlowingPainter extends CustomPainter {
  const _FlowingPainter(this.t);

  final double t;

  static const List<Color> _colors = <Color>[
    Color(0xFF2B7BD9),
    Color(0xFF7B4DD8),
    Color(0xFF2FB3B5),
    Color(0xFFE05BF0),
    Color(0xFF3AA0E0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double angle = t * 2 * math.pi * 2;
    final Paint paint = Paint()
      ..shader = LinearGradient(
        colors: _colors,
        transform: GradientRotation(angle),
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_FlowingPainter oldDelegate) => oldDelegate.t != t;
}
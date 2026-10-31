import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 转盘（模拟）时钟：12 刻度盘 + 时/分/秒三针，白色，每秒刷新。
class AnalogDialClock extends StatefulWidget {
  const AnalogDialClock({super.key});

  @override
  State<AnalogDialClock> createState() => _AnalogDialClockState();
}

class _AnalogDialClockState extends State<AnalogDialClock> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DialPainter(_now),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.now);

  final DateTime now;

  static const Color _white = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) / 2;

    // 表盘
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _white,
    );

    // 60 格刻度（每 5 格加长）
    final Paint tickPaint = Paint()
      ..color = _white
      ..strokeWidth = 2;
    for (int i = 0; i < 60; i++) {
      final double theta = i * math.pi / 30;
      final bool major = i % 5 == 0;
      final double r0 = radius - (major ? 14 : 6);
      canvas.drawLine(
        center + Offset(math.sin(theta), -math.cos(theta)) * r0,
        center + Offset(math.sin(theta), -math.cos(theta)) * (radius - 2),
        tickPaint,
      );
    }

    // 时/分/秒针
    final int hour = now.hour % 12;
    final int minute = now.minute;
    final double second = now.second + now.millisecond / 1000;

    _drawHand(canvas, center, radius * 0.5,
        (hour + minute / 60) * math.pi / 6, _white, 6);
    _drawHand(canvas, center, radius * 0.72,
        (minute + second / 60) * math.pi / 30, _white, 4);
    _drawHand(canvas, center, radius * 0.82, second * math.pi / 30,
        const Color(0xFFE05BF0), 2);

    // 中心轴
    canvas.drawCircle(center, 6, Paint()..color = _white);
  }

  void _drawHand(Canvas canvas, Offset center, double length, double angle,
      Color color, double width) {
    final Offset end = center + Offset(math.sin(angle), -math.cos(angle)) * length;
    canvas.drawLine(center, end, Paint()..color = color..strokeWidth = width);
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.now != now;
}
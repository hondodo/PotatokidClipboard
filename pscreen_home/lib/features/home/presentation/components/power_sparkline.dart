import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/power_sample.dart';

/// 功率趋势迷你图：固定宽度内绘制最近 [window] 的功率折线（Windows 任务管理器风格）。
///
/// - 右侧锚定「现在」，左侧锚定「现在 − window」；启动初期数据只占右端，
///   随时间向左填满；
/// - 网格 + 渐变填充 + 折线，右上角显示窗口内最大功率，左下角显示窗口时长；
/// - 纯 `CustomPaint`，重绘开销极低（每采样周期一次）；
/// - 绘制时自动按逻辑像素分桶、每桶保留最小/最大值，尖峰不丢，
///   因此 24 小时高频采样的绘制开销与数据量基本无关。
class PowerSparkline extends StatelessWidget {
  const PowerSparkline({
    super.key,
    required this.samples,
    this.window = const Duration(hours: 24),
    this.height = 72,
    this.accent = const Color(0xFF8BC34A),
    this.showLabels = true,
  });

  final List<PowerSample> samples;
  final Duration window;

  /// 固定高度；传 null 时占满父级约束（用于 `Expanded` 自适应剩余空间）。
  final double? height;
  final Color accent;

  /// 是否绘制最大值 / 时间轴标签（首页小卡可关闭）。
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget painter = CustomPaint(
      painter: _SparklinePainter(
        samples: samples,
        window: window,
        accent: accent,
        showLabels: showLabels,
        gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        labelColor: theme.colorScheme.outline,
      ),
    );
    if (height == null) {
      return SizedBox.expand(child: painter);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: painter,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.window,
    required this.accent,
    required this.showLabels,
    required this.gridColor,
    required this.labelColor,
  });

  final List<PowerSample> samples;
  final Duration window;
  final Color accent;
  final bool showLabels;
  final Color gridColor;
  final Color labelColor;

  static const double _labelFontSize = 10;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (samples.isNotEmpty) {
      final List<Offset> points = _points(size);
      if (points.isNotEmpty) {
        _drawFill(canvas, size, points);
        _drawLine(canvas, points);
      }
    }

    if (showLabels) {
      _drawLabels(canvas, size);
    }
  }

  List<Offset> _points(Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) {
      return const <Offset>[];
    }
    final DateTime now = DateTime.now();
    final int windowStartMs = now.subtract(window).millisecondsSinceEpoch;
    final int windowMs = window.inMilliseconds;
    if (windowMs <= 0) return const <Offset>[];

    double maxWatts = 0;
    for (final PowerSample s in samples) {
      if (s.watts > maxWatts) maxWatts = s.watts;
    }
    final double yMax = maxWatts <= 0 ? 1 : maxWatts * 1.15;

    // 自动降采样：每个逻辑像素一个桶，桶内保留最小 / 最大两个点。
    final List<PowerSample> plotted = downsamplePowerSamples(
      samples: samples,
      now: now,
      window: window,
      width: size.width,
    );

    return plotted.map((PowerSample s) {
      final double t =
          (s.at.millisecondsSinceEpoch - windowStartMs).toDouble();
      final double x = (t / windowMs) * size.width;
      final double y = size.height - (s.watts / yMax) * size.height;
      return Offset(
        x.clamp(0.0, size.width),
        y.clamp(0.0, size.height),
      );
    }).toList(growable: false);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // 横线：25% / 50% / 75%
    for (final double f in const <double>[0.25, 0.5, 0.75]) {
      final double y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 竖线：20% / 40% / 60% / 80%
    for (final double f in const <double>[0.2, 0.4, 0.6, 0.8]) {
      final double x = size.width * f;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawFill(Canvas canvas, Size size, List<Offset> points) {
    final Path fill = Path()
      ..moveTo(points.first.dx, size.height);
    for (final Offset p in points) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(points.last.dx, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            accent.withValues(alpha: 0.32),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  void _drawLine(Canvas canvas, List<Offset> points) {
    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset p in points) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLabels(Canvas canvas, Size size) {
    double maxWatts = 0;
    for (final PowerSample s in samples) {
      if (s.watts > maxWatts) maxWatts = s.watts;
    }
    final String maxLabel = '${maxWatts.round()} W';

    _text(canvas, maxLabel, Offset(size.width, 0), alignRight: true);
    _text(canvas, '0', Offset(size.width, size.height),
        alignRight: true, bottom: true);
    _text(canvas, _windowLabel(), Offset(0, size.height), bottom: true);
  }

  String _windowLabel() {
    if (window.inHours >= 1) {
      final int h = window.inHours;
      return h == 1 ? '1小时前' : '$h小时前';
    }
    return '${window.inMinutes}分钟前';
  }

  void _text(Canvas canvas, String text, Offset anchor,
      {bool alignRight = false, bool bottom = false}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: _labelFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double dx = alignRight ? anchor.dx - painter.width : anchor.dx;
    final double dy = bottom ? anchor.dy - painter.height : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.window != window ||
        oldDelegate.accent != accent ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

/// 绘制用的采样点：保留原始值与映射后的横坐标。
class _Plotted {
  const _Plotted({required this.sample, required this.x});

  final PowerSample sample;
  final double x;
}

/// 按逻辑像素宽度分桶降采样：每桶保留时间顺序上的最小值 / 最大值。
///
/// 这不是数据层操作：`PowerHistoryStore` 仍保留完整的 24 小时采样点，
/// 仅在绘制前把「一个像素里挤了几十个点」压缩成 min/max 两个点，
/// 既保留尖峰，又把线段数收敛到约 `2 × 图表宽度`。
@visibleForTesting
List<PowerSample> downsamplePowerSamples({
  required List<PowerSample> samples,
  required DateTime now,
  required Duration window,
  required double width,
}) {
  if (samples.isEmpty || width <= 0 || window <= Duration.zero) {
    return const <PowerSample>[];
  }
  final int windowStartMs = now.subtract(window).millisecondsSinceEpoch;
  final int windowMs = window.inMilliseconds;
  if (windowMs <= 0) return const <PowerSample>[];

  // 先按时间窗过滤并映射横坐标。
  final List<_Plotted> visible = <_Plotted>[];
  for (final PowerSample s in samples) {
    final double t = (s.at.millisecondsSinceEpoch - windowStartMs).toDouble();
    final double x = (t / windowMs) * width;
    if (x < -2 || x > width + 2) continue;
    visible.add(_Plotted(sample: s, x: x));
  }
  if (visible.isEmpty) return const <PowerSample>[];

  final List<_Plotted> plotted = _downsamplePlotted(visible, width);
  return plotted.map((_Plotted p) => p.sample).toList(growable: false);
}

/// 采样点横坐标递增，顺序扫描分桶即可。
List<_Plotted> _downsamplePlotted(List<_Plotted> input, double width) {
  final int buckets = width.ceil();
  final int maxPoints = buckets * 2;
  if (buckets <= 0 || input.length <= maxPoints) return input;

  final int lastIndex = input.length - 1;
  final List<_Plotted> out = <_Plotted>[];
  int start = 0;
  for (int b = 0; b < buckets && start <= lastIndex; b++) {
    final double bucketEnd = b + 1.0;
    int end = start;
    while (end <= lastIndex && input[end].x < bucketEnd) {
      end += 1;
    }
    if (end == start) continue;

    int minIndex = start;
    int maxIndex = start;
    for (int i = start + 1; i < end; i++) {
      if (input[i].sample.watts < input[minIndex].sample.watts) {
        minIndex = i;
      }
      if (input[i].sample.watts > input[maxIndex].sample.watts) {
        maxIndex = i;
      }
    }

    if (minIndex == maxIndex) {
      out.add(input[start]);
    } else if (minIndex < maxIndex) {
      out
        ..add(input[minIndex])
        ..add(input[maxIndex]);
    } else {
      out
        ..add(input[maxIndex])
        ..add(input[minIndex]);
    }
    start = end;
  }

  // 收尾：保证曲线一直画到最右端（包括超出右边界的少量余量点）。
  if (start <= lastIndex) out.add(input[lastIndex]);
  return out;
}

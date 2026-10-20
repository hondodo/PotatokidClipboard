import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

/// 指标趋势迷你图：固定宽度内绘制最近 [window] 的折线（Windows 任务管理器风格）。
///
/// - 右侧锚定「现在」，左侧锚定「现在 − window」；启动初期数据只占右端，
///   随时间向左填满；
/// - 网格 + 渐变填充 + 折线，右上角显示窗口内最大值（带 [unit]），
///   左下角显示窗口时长；
/// - 支持负值（如零下温度），y 轴按实际 min/max 自适应；
/// - [gapThreshold] 非空时，相邻点时间差超过该值即断开（缺数据留空）；
/// - 纯 `CustomPaint`，重绘开销极低（每采样周期一次）；
/// - 绘制时自动按逻辑像素分桶、每桶保留最小/最大值，尖峰不丢，
///   因此 24 小时高频采样的绘制开销与数据量基本无关。
class MetricSparkline extends StatelessWidget {
  const MetricSparkline({
    super.key,
    required this.samples,
    this.window = const Duration(hours: 24),
    this.height = 72,
    this.accent = const Color(0xFF8BC34A),
    this.showLabels = true,
    this.unit = 'W',
    this.gapThreshold,
  });

  final List<MetricSample> samples;
  final Duration window;

  /// 固定高度；传 null 时占满父级约束（用于 `Expanded` 自适应剩余空间）。
  final double? height;
  final Color accent;

  /// 是否绘制最大值 / 时间轴标签（首页小卡可关闭）。
  final bool showLabels;

  /// y 轴 / 标签单位（W / °C / %）。
  final String unit;

  /// 断线阈值：相邻点间隔超过该值时切成新的一段；null 表示始终连续。
  final Duration? gapThreshold;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget painter = CustomPaint(
      painter: _SparklinePainter(
        samples: samples,
        window: window,
        accent: accent,
        showLabels: showLabels,
        unit: unit,
        gapThreshold: gapThreshold,
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
    required this.unit,
    required this.gapThreshold,
    required this.gridColor,
    required this.labelColor,
  });

  final List<MetricSample> samples;
  final Duration window;
  final Color accent;
  final bool showLabels;
  final String unit;
  final Duration? gapThreshold;
  final Color gridColor;
  final Color labelColor;

  static const double _labelFontSize = 10;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    for (final List<Offset> segment in _segments(size)) {
      if (segment.length < 2) continue;
      _drawFill(canvas, size, segment);
      _drawLine(canvas, segment);
    }

    if (showLabels) {
      _drawLabels(canvas, size);
    }
  }

  ({double min, double max}) _valueRange(List<MetricSample> plotted) {
    double lo = plotted.first.value;
    double hi = plotted.first.value;
    for (final MetricSample s in plotted) {
      final double pointLo = math.min(s.value, s.min ?? s.value);
      final double pointHi = math.max(s.value, s.max ?? s.value);
      if (pointLo < lo) lo = pointLo;
      if (pointHi > hi) hi = pointHi;
    }
    if (hi - lo < 0.001) {
      lo = lo > 0 ? lo * 0.85 : lo * 1.15;
      hi = hi > 0 ? hi * 1.15 : hi * 0.85;
      if (hi - lo < 0.001) return (min: 0, max: 1);
    } else {
      final double pad = (hi - lo) * 0.15;
      lo -= pad;
      hi += pad;
    }
    return (min: lo, max: hi);
  }

  List<List<Offset>> _segments(Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) {
      return const <List<Offset>>[];
    }
    final DateTime now = DateTime.now();
    final int windowStartMs = now.subtract(window).millisecondsSinceEpoch;
    final int windowMs = window.inMilliseconds;
    if (windowMs <= 0) return const <List<Offset>>[];

    final List<MetricSample> plotted = downsampleMetricSamples(
      samples: samples,
      now: now,
      window: window,
      width: size.width,
    );
    if (plotted.isEmpty) return const <List<Offset>>[];

    final ({double min, double max}) range = _valueRange(plotted);
    final double span = range.max - range.min;

    return splitByGap(plotted, gapThreshold).map((List<MetricSample> part) {
      return part.map((MetricSample s) {
        final double t =
            (s.at.millisecondsSinceEpoch - windowStartMs).toDouble();
        final double x = (t / windowMs) * size.width;
        final double y =
            size.height - ((s.value - range.min) / span) * size.height;
        return Offset(
          x.clamp(0.0, size.width),
          y.clamp(0.0, size.height),
        );
      }).toList(growable: false);
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
    final Path fill = Path()..moveTo(points.first.dx, size.height);
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
    if (samples.isEmpty) return;
    final ({double min, double max}) range = _valueRange(samples);
    _text(canvas, '${_fmt(range.max)} $unit', Offset(size.width, 0),
        alignRight: true);
    _text(canvas, _fmt(range.min), Offset(size.width, size.height),
        alignRight: true, bottom: true);
    _text(canvas, _windowLabel(), Offset(0, size.height), bottom: true);
  }

  static String _fmt(double v) =>
      v.abs() >= 100 ? '${v.round()}' : v.toStringAsFixed(1);

  String _windowLabel() {
    if (window.inDays >= 1) return '${window.inDays}天前';
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
        oldDelegate.unit != unit ||
        oldDelegate.gapThreshold != gapThreshold ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

/// 按相邻点时间差切段：超过 [gap] 处断开（null 时整条为一段）。
@visibleForTesting
List<List<MetricSample>> splitByGap(  List<MetricSample> samples,
  Duration? gap,
) {
  if (samples.isEmpty) return const <List<MetricSample>>[];
  if (gap == null) return <List<MetricSample>>[samples];
  final List<List<MetricSample>> out = <List<MetricSample>>[];
  List<MetricSample> current = <MetricSample>[samples.first];
  for (int i = 1; i < samples.length; i++) {
    if (samples[i].at.difference(samples[i - 1].at) > gap) {
      out.add(current);
      current = <MetricSample>[];
    }
    current.add(samples[i]);
  }
  out.add(current);
  return out;
}

/// 绘制用的采样点：保留原始值与映射后的横坐标。
class _Plotted {
  const _Plotted({required this.sample, required this.x});

  final MetricSample sample;
  final double x;
}

/// 按逻辑像素宽度分桶降采样：每桶保留时间顺序上的最小值 / 最大值。
///
/// 这不是数据层操作：`MetricHistoryStore` 仍保留完整的 24 小时采样点，
/// 仅在绘制前把「一个像素里挤了几十个点」压缩成 min/max 两个点，
/// 既保留尖峰，又把线段数收敛到约 `2 × 图表宽度`。
@visibleForTesting
List<MetricSample> downsampleMetricSamples({
  required List<MetricSample> samples,
  required DateTime now,
  required Duration window,
  required double width,
}) {
  if (samples.isEmpty || width <= 0 || window <= Duration.zero) {
    return const <MetricSample>[];
  }
  final int windowStartMs = now.subtract(window).millisecondsSinceEpoch;
  final int windowMs = window.inMilliseconds;
  if (windowMs <= 0) return const <MetricSample>[];

  // 先按时间窗过滤并映射横坐标。
  final List<_Plotted> visible = <_Plotted>[];
  for (final MetricSample s in samples) {
    final double t = (s.at.millisecondsSinceEpoch - windowStartMs).toDouble();
    final double x = (t / windowMs) * width;
    if (x < -2 || x > width + 2) continue;
    visible.add(_Plotted(sample: s, x: x));
  }
  if (visible.isEmpty) return const <MetricSample>[];

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
      if (input[i].sample.value < input[minIndex].sample.value) {
        minIndex = i;
      }
      if (input[i].sample.value > input[maxIndex].sample.value) {
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

/// 断线阈值自适应：HA 明细只记录「状态变化」，长时间恒定的传感器
/// 相邻点可能相隔数小时。此时按中位间隔放大阈值，避免把恒定值误判成缺数据。
Duration? adaptiveGap(Duration? base, List<MetricSample> samples) {
  if (base == null || samples.length < 3) return base;
  final List<int> gaps = <int>[];
  for (int i = 1; i < samples.length; i++) {
    gaps.add(samples[i].at.difference(samples[i - 1].at).inMilliseconds);
  }
  gaps.sort();
  final int median = gaps[gaps.length ~/ 2];
  final int floorMs = math.max(base.inMilliseconds, median * 5);
  return Duration(milliseconds: floorMs);
}

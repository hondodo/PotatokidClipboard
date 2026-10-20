import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 指标曲线卡：range 切换 + metric 切换 + 曲线。
class MetricChartCard extends StatefulWidget {
  const MetricChartCard({
    super.key,
    required this.service,
    required this.deviceId,
    required this.entityIds,
    this.initialMetric = Metric.power,
    this.initialRange = HistoryRange.h24,
  });

  final HistoryService service;
  final String deviceId;
  final Map<Metric, String> entityIds;
  final Metric initialMetric;
  final HistoryRange initialRange;

  List<Metric> get availableMetrics =>
      entityIds.keys.toList(growable: false);

  @override
  State<MetricChartCard> createState() => _MetricChartCardState();
}

class _MetricChartCardState extends State<MetricChartCard> {
  late Metric _metric = widget.availableMetrics.contains(widget.initialMetric)
      ? widget.initialMetric
      : widget.availableMetrics.first;
  late HistoryRange _range = widget.initialRange;
  List<MetricSample>? _samples;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? entityId = widget.entityIds[_metric];
    if (entityId == null) {
      if (mounted) setState(() => _samples = const <MetricSample>[]);
      return;
    }
    final List<MetricSample> samples = await widget.service.load(
      deviceId: widget.deviceId,
      metric: _metric,
      range: _range,
      entityId: entityId,
    );
    if (!mounted) return;
    setState(() => _samples = samples);
  }

  /// 明细段的断线阈值：采样越密、窗口越长，允许的间隔越大。
  static Duration? _gapFor(HistoryRange range) {
    switch (range) {
      case HistoryRange.h1:
      case HistoryRange.h6:
        return const Duration(minutes: 2);
      case HistoryRange.h12:
      case HistoryRange.h24:
        return const Duration(minutes: 10);
      case HistoryRange.week:
        return const Duration(hours: 1);
      case HistoryRange.month:
      case HistoryRange.year:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final HistoryRange r in HistoryRange.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r.label),
                        selected: r == _range,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _range = r);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final Metric m in widget.availableMetrics)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(m.label),
                        selected: m == _metric,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _metric = m);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_samples != null)
              MetricSparkline(
                samples: _samples!,
                window: _range.duration,
                height: 120,
                unit: _metric.unit,
                gapThreshold: adaptiveGap(_gapFor(_range), _samples!),
              ),
          ],
        ),
      ),
    );
  }
}

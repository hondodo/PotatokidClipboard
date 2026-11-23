import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 指标曲线卡：共享 range 切换，功率 / 温度 / 湿度分区同时展示（无需切换）。
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.service,
    required this.deviceId,
    required this.sources,
    this.initialRange = HistoryRange.h24,
    this.isConnected = true,
  });

  final HistoryService service;
  final String deviceId;
  final Map<Metric, MetricSource> sources;
  final HistoryRange initialRange;

  /// HA 是否已连接；离线时先不拉历史，重连后自动补拉。
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: MetricChartContent(
          service: service,
          deviceId: deviceId,
          sources: sources,
          initialRange: initialRange,
          isConnected: isConnected,
        ),
      ),
    );
  }
}

/// 曲线内容：range 切换 + 各指标分区，可嵌入其他卡片。
class MetricChartContent extends StatefulWidget {
  const MetricChartContent({
    super.key,
    required this.service,
    required this.deviceId,
    required this.sources,
    this.initialRange = HistoryRange.h24,
    this.isConnected = true,
  });

  final HistoryService service;
  final String deviceId;
  final Map<Metric, MetricSource> sources;
  final HistoryRange initialRange;

  /// HA 是否已连接；离线时先不拉历史，重连后自动补拉。
  final bool isConnected;

  List<Metric> get metrics =>
      sources.keys.toList(growable: false)
        ..sort((Metric a, Metric b) => a.index - b.index);

  @override
  State<MetricChartContent> createState() => _MetricChartContentState();
}

class _MetricChartContentState extends State<MetricChartContent> {
  late HistoryRange _range = widget.initialRange;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    onSelected: (_) => setState(() => _range = r),
                  ),
                ),
            ],
          ),
        ),
        for (final Metric metric in widget.metrics) ...<Widget>[
          const SizedBox(height: 18),
          _MetricSection(
            key: ValueKey<Metric>(metric),
            service: widget.service,
            deviceId: widget.deviceId,
            metric: metric,
            source: widget.sources[metric]!,
            range: _range,
            isConnected: widget.isConnected,
          ),
        ],
      ],
    );
  }
}

/// 单个指标分区：标题 + 曲线，随内存采样实时刷新。
class _MetricSection extends StatefulWidget {
  const _MetricSection({
    super.key,
    required this.service,
    required this.deviceId,
    required this.metric,
    required this.source,
    required this.range,
    required this.isConnected,
  });

  final HistoryService service;
  final String deviceId;
  final Metric metric;
  final MetricSource source;
  final HistoryRange range;
  final bool isConnected;

  @override
  State<_MetricSection> createState() => _MetricSectionState();
}

class _MetricSectionState extends State<_MetricSection> {
  List<MetricSample>? _samples;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isConnected) _load();
  }

  @override
  void didUpdateWidget(covariant _MetricSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool becameConnected = !oldWidget.isConnected && widget.isConnected;
    if (oldWidget.range != widget.range ||
        oldWidget.service != widget.service ||
        oldWidget.deviceId != widget.deviceId) {
      _load();
    } else if (becameConnected) {
      // 离线时进入详情 / 重连：连接恢复后补拉历史。
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.isConnected) return;
    final int token = ++_loadToken;
    try {
      final List<MetricSample> samples = await widget.service.load(
        deviceId: widget.deviceId,
        metric: widget.metric,
        range: widget.range,
        source: widget.source,
      );
      // 快速切换 range 时丢弃过期结果。
      if (!mounted || token != _loadToken) return;
      setState(() => _samples = samples);
    } catch (e) {
      // 离线 / 历史接口不可用：保留空图区，不要把异常抛给框架。
      if (!mounted || token != _loadToken) return;
      if (_samples == null) {
        setState(() => _samples = const <MetricSample>[]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MetricSample>? loaded = _samples;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(widget.metric.label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              widget.metric.unit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loaded == null)
          const SizedBox(height: 110)
        else
          ValueListenableBuilder<List<MetricSample>>(
            valueListenable: widget.service.watch(
              widget.deviceId,
              widget.metric,
            ),
            builder: (BuildContext context, _, Widget? child) {
              final List<MetricSample> merged = widget.service.mergeLive(
                widget.deviceId,
                widget.metric,
                loaded,
              );
              return MetricSparkline(
                samples: merged,
                window: widget.range.duration,
                height: 110,
                unit: widget.metric.unit,
              );
            },
          ),
      ],
    );
  }
}

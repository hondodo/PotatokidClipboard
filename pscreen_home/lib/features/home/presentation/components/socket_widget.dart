import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 智能插座卡片：开关 + 当前功率 + 功率趋势 + 累计电量。
class SocketWidget extends StatefulWidget {
  const SocketWidget({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.onOpenDetail,
    this.history,
    this.historyService,
    this.deviceId,
    this.powerSource,
  });

  final SocketSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  /// 内存功率采样订阅；null 则仅使用 [historyService] 或隐藏趋势图。
  final ValueListenable<List<MetricSample>>? history;

  /// 历史服务；提供后启动时回填 24h 曲线，与详情页一致。
  final HistoryService? historyService;
  final String? deviceId;
  final MetricSource? powerSource;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  State<SocketWidget> createState() => _SocketWidgetState();
}

class _SocketWidgetState extends State<SocketWidget> {
  List<MetricSample>? _history;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(SocketWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.powerSource?.entityId != widget.powerSource?.entityId ||
        oldWidget.powerSource?.attribute != widget.powerSource?.attribute ||
        oldWidget.historyService != widget.historyService) {
      _history = null;
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final HistoryService? service = widget.historyService;
    final String? deviceId = widget.deviceId;
    final MetricSource? source = widget.powerSource;
    if (service == null || deviceId == null || source == null) return;
    final int token = ++_loadToken;
    final List<MetricSample> samples = await service.load(
      deviceId: deviceId,
      metric: Metric.power,
      range: HistoryRange.h24,
      source: source,
    );
    if (!mounted || token != _loadToken) return;
    setState(() => _history = samples);
  }

  bool get _hasChart =>
      (widget.historyService != null &&
          widget.deviceId != null &&
          widget.powerSource != null) ||
      widget.history != null;

  Widget _buildChart() {
    final HistoryService? service = widget.historyService;
    final String? deviceId = widget.deviceId;
    final MetricSource? source = widget.powerSource;
    if (service != null && deviceId != null && source != null) {
      return ValueListenableBuilder<List<MetricSample>>(
        valueListenable: service.watch(deviceId, Metric.power),
        builder: (BuildContext context, List<MetricSample> _, _) {
          return MetricSparkline(
            height: null,
            showLabels: false,
            samples: service.mergeLive(
              deviceId,
              Metric.power,
              _history ?? const <MetricSample>[],
            ),
          );
        },
      );
    }
    return ValueListenableBuilder<List<MetricSample>>(
      valueListenable: widget.history!,
      builder: (BuildContext context, List<MetricSample> samples, _) {
        return MetricSparkline(
          height: null,
          showLabels: false,
          samples: samples,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final SocketSummary summary = widget.summary;
    final bool isToggling = widget.isToggling;
    final VoidCallback onToggle = widget.onToggle;
    final String? areaLabel = widget.areaLabel;
    final VoidCallback? onOpenDetail = widget.onOpenDetail;
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    const Color accent = SocketWidget._accent;
    final Color color = summary.hasFault
        ? theme.colorScheme.error
        : (on ? accent : theme.colorScheme.outline);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.outlet_rounded,
                      size: 19,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          summary.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${areaLabel ?? '未分配房间'} · ${summary.statusLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关闭插座' : '开启插座',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isToggling ? null : onToggle,
                    icon: Icon(
                      Icons.power_settings_new_rounded,
                      size: 19,
                      color: color,
                    ),
                  ),
                ],
              ),
              if (_hasChart) ...<Widget>[
                const SizedBox(height: 2),
                Expanded(child: _buildChart()),
                const SizedBox(height: 4),
              ] else
                const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    summary.stats.currentPowerLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '累计 ${summary.stats.totalLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

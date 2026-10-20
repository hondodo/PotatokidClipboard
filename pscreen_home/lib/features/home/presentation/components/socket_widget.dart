import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/power_sample.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/power_sparkline.dart';

/// 智能插座卡片：开关 + 当前功率 + 功率趋势 + 累计电量。
class SocketWidget extends StatelessWidget {
  const SocketWidget({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.onOpenDetail,
    this.history,
  });

  final SocketSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  /// 功率历史订阅；null 则不绘制趋势图。
  final ValueListenable<List<PowerSample>>? history;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final Color color = summary.hasFault
        ? theme.colorScheme.error
        : (on ? _accent : theme.colorScheme.outline);

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
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.outlet_rounded,
                      size: 19,
                      color: _accent,
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
              if (history != null) ...<Widget>[
                const SizedBox(height: 2),
                Expanded(
                  child: ValueListenableBuilder<List<PowerSample>>(
                    valueListenable: history!,
                    builder:
                        (BuildContext context, List<PowerSample> samples, _) {
                      return PowerSparkline(
                        height: null,
                        showLabels: false,
                        samples: samples,
                      );
                    },
                  ),
                ),
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

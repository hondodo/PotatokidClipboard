import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/socket_quick_switch.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 智能插座详情面板：当前功率、功率趋势、累计电量、设备温度、开关次数。
class SocketControlPanel extends StatelessWidget {
  const SocketControlPanel({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.quickSwitches = const <SocketQuickSwitch>[],
    this.onQuickSwitchToggled,
    this.indicatorLightEntityId,
    this.indicatorLightOn = false,
    this.onIndicatorLightToggled,
    this.history,
  });

  final SocketSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;

  /// 功率历史订阅；null 则不绘制趋势图。
  final ValueListenable<List<MetricSample>>? history;

  /// 插座次级开关（童锁 / 定时），空列表则不渲染该区。
  final List<SocketQuickSwitch> quickSwitches;

  /// 快捷开关点击：参数为实体 id；null 时不可点。
  final ValueChanged<String>? onQuickSwitchToggled;

  /// 指示灯实体 id（light 域），null 则不显示灯泡开关。
  final String? indicatorLightEntityId;
  final bool indicatorLightOn;
  final VoidCallback? onIndicatorLightToggled;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.outlet_rounded,
                    color: on ? _accent : theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: summary.hasFault
                              ? theme.colorScheme.error
                              : (on ? _accent : theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: on,
                  onChanged: isToggling ? null : (bool _) => onToggle(),
                  activeThumbColor: _accent,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '当前功率',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.stats.currentPowerLabel,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '累计用电',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.stats.totalLabel,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (history != null)
              ValueListenableBuilder<List<MetricSample>>(
                valueListenable: history!,
                builder:
                    (BuildContext context, List<MetricSample> samples, _) {
                  return MetricSparkline(samples: samples);
                },
              ),
            if (history != null) const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: <Widget>[
                _Info(
                  icon: Icons.thermostat_rounded,
                  label: '设备温度',
                  value: summary.stats.deviceTemperature == null
                      ? '—'
                      : '${summary.stats.deviceTemperature}°C',
                ),
                _Info(
                  icon: Icons.swap_horiz_rounded,
                  label: '开关次数',
                  value: summary.stats.switchCount?.toString() ?? '—',
                ),
                _Info(
                  icon: Icons.info_outline_rounded,
                  label: '故障',
                  value: summary.hasFault ? summary.fault! : '无故障',
                ),
              ],
            ),
            if (quickSwitches.isNotEmpty || indicatorLightEntityId != null)
              ...<Widget>[
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final SocketQuickSwitch s in quickSwitches)
                      FilterChip(
                        label: Text(s.label),
                        selected: s.isOn,
                        showCheckmark: false,
                        avatar: Icon(
                          s.isOn
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color:
                              s.isOn ? _accent : theme.colorScheme.outline,
                        ),
                        onSelected: onQuickSwitchToggled == null
                            ? null
                            : (bool _) => onQuickSwitchToggled!(s.entityId),
                      ),
                    if (indicatorLightEntityId != null)
                      FilterChip(
                        label: const Text('指示灯'),
                        selected: indicatorLightOn,
                        showCheckmark: false,
                        avatar: Icon(
                          indicatorLightOn
                              ? Icons.lightbulb_rounded
                              : Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: indicatorLightOn
                              ? _accent
                              : theme.colorScheme.outline,
                        ),
                        onSelected: onIndicatorLightToggled == null
                            ? null
                            : (bool _) => onIndicatorLightToggled!(),
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

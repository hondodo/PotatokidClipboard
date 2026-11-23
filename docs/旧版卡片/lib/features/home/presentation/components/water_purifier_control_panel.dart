import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/water_purifier_summary.dart';

/// 净水器详情：TDS / 水温 / 滤芯寿命 / 假期模式等。
class WaterPurifierControlPanel extends StatelessWidget {
  const WaterPurifierControlPanel({
    super.key,
    required this.summary,
    required this.onHolidayToggle,
    required this.onPipelineToggle,
    required this.onAlarmToggle,
  });

  final WaterPurifierSummary summary;
  final VoidCallback? onHolidayToggle;
  final VoidCallback? onPipelineToggle;
  final VoidCallback? onAlarmToggle;

  static const Color _accent = Color(0xFF4DD0C4);

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
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: _accent,
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
                              : _accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '直饮水 TDS',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      Text(
                        summary.tds?.toString() ?? '—',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _accent,
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
                      '进水温度',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    Text(
                      summary.temperature == null
                          ? '—'
                          : '${summary.temperature}°C',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final WaterFilter filter in summary.filters) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      filter.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${filter.lifePercent}%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: filter.lifePercent <= 20
                          ? theme.colorScheme.error
                          : _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (filter.lifePercent / 100).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: filter.lifePercent <= 20
                      ? theme.colorScheme.error
                      : _accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                filter.leftDays == null ? '剩余寿命' : '剩余约 ${filter.leftDays} 天',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Divider(height: 1),
            const SizedBox(height: 8),
            _SwitchRow(
              label: '假期模式',
              value: summary.holidayMode,
              onTap: onHolidayToggle,
            ),
            _SwitchRow(
              label: '管线机对接',
              value: summary.pipelineConnected,
              onTap: onPipelineToggle,
            ),
            _SwitchRow(
              label: '提示音',
              value: summary.alarmOn,
              onTap: onAlarmToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        Switch(
          value: value,
          onChanged: onTap == null ? null : (bool _) => onTap!(),
          activeThumbColor: WaterPurifierControlPanel._accent,
        ),
      ],
    );
  }
}

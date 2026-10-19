import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';

/// 通用用电信息卡：当前功率 + 累计电量（有则显示）+ 设备温度 / 开关次数。
class PowerStatsCard extends StatelessWidget {
  const PowerStatsCard({super.key, required this.stats, this.title = '用电信息'});

  final PowerStats stats;
  final String title;

  static const Color _accent = Color(0xFF64B5F6);

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
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
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
                        stats.currentPowerLabel,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (stats.totalKwh != null)
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
                        stats.totalLabel,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (stats.deviceTemperature != null ||
                stats.switchCount != null) ...<Widget>[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: <Widget>[
                  if (stats.deviceTemperature != null)
                    _Info(
                      label: '设备温度',
                      value: '${stats.deviceTemperature}°C',
                    ),
                  if (stats.switchCount != null)
                    _Info(
                      label: '开关次数',
                      value: '${stats.switchCount}',
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
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      '$label $value',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

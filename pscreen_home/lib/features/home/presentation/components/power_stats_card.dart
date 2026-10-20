import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 通用用电信息卡：当前功率 + 累计电量（有则显示）+ 功率趋势图 + 设备温度 / 开关次数。
///
/// 有「当前功率」的设备（智能插座、空调插座等）统一用本卡展示用电信息；
/// 传入 [history] 时绘制最近 1 小时的功率趋势图（仅内存，不持久化）。
class PowerStatsCard extends StatelessWidget {
  const PowerStatsCard({
    super.key,
    required this.stats,
    this.title = '用电信息',
    this.history,
  });

  final PowerStats stats;
  final String title;

  /// 功率历史订阅；null 则不绘制趋势图。
  final ValueListenable<List<MetricSample>>? history;

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
            if (history != null) ...<Widget>[
              const SizedBox(height: 12),
              ValueListenableBuilder<List<MetricSample>>(
                valueListenable: history!,
                builder:
                    (BuildContext context, List<MetricSample> samples, _) {
                  return MetricSparkline(samples: samples);
                },
              ),
            ],
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

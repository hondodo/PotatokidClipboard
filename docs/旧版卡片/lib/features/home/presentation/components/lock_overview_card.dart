import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/lock_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/lock_status_icons.dart';

/// 门锁详情页顶部主信息卡：上锁状态 + 各电池电量 + 电量更新时间。
///
/// 与「用电信息」卡同一形态：一个区域集中展示门锁关键数据。
class LockOverviewCard extends StatelessWidget {
  const LockOverviewCard({super.key, required this.summary});

  final LockSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lockColor =
        LockStatusIcons.lockColor(theme, summary.locked);

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
              '门锁状态',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Icon(
                  LockStatusIcons.lockIcon(summary.locked),
                  size: 44,
                  color: lockColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    summary.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: lockColor,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.batteries.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: <Widget>[
                  for (final LockBattery battery in summary.batteries)
                    _BatteryInfo(battery: battery),
                ],
              ),
            ],
            if (summary.batteryUpdatedAt != null) ...<Widget>[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '电量更新时间',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.batteryUpdatedLabel ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

/// 单块电池：图标 + 百分比 + 电池名。
class _BatteryInfo extends StatelessWidget {
  const _BatteryInfo({required this.battery});

  final LockBattery battery;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        LockStatusIcons.batteryColor(theme, battery.percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          battery.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              LockStatusIcons.batteryIcon(battery.percent),
              size: 24,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              battery.valueLabel,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/lock_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/lock_status_icons.dart';

/// 门锁设备卡：是否已上锁 + 各电池剩余电量 + 电量更新时间。
///
/// 门锁属于安全设备，外层卡**不提供快捷开关按钮**，点击整张卡进入详情页。
class LockWidget extends StatelessWidget {
  const LockWidget({
    super.key,
    required this.summary,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onOpenDetail,
  });

  final LockSummary summary;
  final String? areaLabel;
  final bool showAreaInTitle;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color lockColor =
        LockStatusIcons.lockColor(theme, summary.locked);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: lockColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.sensor_door_rounded,
                      size: 19,
                      color: lockColor,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      cardTitle(
                        title: summary.name,
                        areaLabel: areaLabel,
                        showArea: showAreaInTitle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    areaLabel ?? '未分配房间',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _Meta(
                    icon: LockStatusIcons.lockIcon(summary.locked),
                    text: summary.statusLabel,
                    color: lockColor,
                    bold: true,
                  ),
                  for (final LockBattery battery in summary.batteries)
                    _Meta(
                      icon: LockStatusIcons.batteryIcon(battery.percent),
                      text: '${battery.label} ${battery.valueLabel}',
                      color: LockStatusIcons.batteryColor(
                        theme,
                        battery.percent,
                      ),
                    ),
                ],
              ),
              if (summary.batteryUpdatedShortLabel != null) ...<Widget>[
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '电量更新 ${summary.batteryUpdatedShortLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标 + 文字的小号状态项。
class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    required this.color,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

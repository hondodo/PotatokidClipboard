import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';

/// 油烟机卡片：电源 / 风量 / 灯光 / 延时。
class RangeHoodWidget extends StatelessWidget {
  const RangeHoodWidget({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.onOpenDetail,
  });

  final RangeHoodSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
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
                      Icons.air_rounded,
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
                            color: summary.hasFault
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关闭油烟机' : '开启油烟机',
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
                      color: on ? _accent : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                summary.burnerStatusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: summary.anyBurnerOn
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Text(
                    summary.fanLevel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: on ? _accent : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    summary.lightOn
                        ? Icons.lightbulb_rounded
                        : Icons.lightbulb_outline_rounded,
                    size: 14,
                    color: summary.lightOn
                        ? const Color(0xFFFFB74D)
                        : theme.colorScheme.outline,
                  ),
                  const Spacer(),
                  Text(
                    summary.delayOn ? '延时 ${summary.delayMinutes} 分钟' : '延时关',
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

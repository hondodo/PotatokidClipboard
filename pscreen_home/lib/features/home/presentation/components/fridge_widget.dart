import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';

/// 冰箱快捷卡片：冷藏 / 冷冻 / 变温三舱当前温度与目标温度。
class FridgeWidget extends StatelessWidget {
  const FridgeWidget({
    super.key,
    required this.summary,
    this.areaLabel,
    this.onOpenDetail,
  });

  final FridgeSummary summary;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool warning = summary.hasWarning;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.kitchen_rounded,
                      size: 17,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 7),
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
                            color: warning
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: summary.zones
                    .map((FridgeZone zone) => Expanded(
                          child: Column(
                            children: <Widget>[
                              Text(
                                zone.name,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  height: 1,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Text(
                                '${zone.currentTemperature ?? '--'}°',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: warning
                                      ? theme.colorScheme.error
                                      : _accent,
                                ),
                              ),
                              Text(
                                '目标 ${zone.targetTemperature}°',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  height: 1,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

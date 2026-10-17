import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';

/// 电热水瓶快捷卡片：当前水温 + 状态 + 模式 + 目标温度。
///
/// 卡片不提供开始/停止动作，避免误触；点卡片进入详情操作。
class KettleWidget extends StatelessWidget {
  const KettleWidget({
    super.key,
    required this.summary,
    this.onOpenDetail,
  });

  final KettleSummary summary;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = summary.isActive;

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
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.emoji_food_beverage_rounded,
                      size: 21,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                        const SizedBox(height: 3),
                        Text(
                          '${summary.status} · ${summary.mode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: active
                                ? _accent
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: _format(summary.temperature),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: '°C',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '目标 ${_format(summary.effectiveTargetTemperature)}°C',
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

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';

/// 风扇快捷卡片：模式 + 档位 + 摆风，卡片右上角电源。
///
/// 点卡片其余区域进入详情。
class FanWidget extends StatelessWidget {
  const FanWidget({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.onOpenDetail,
  });

  final FanSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final String detail = summary.isContinuous
        ? (summary.supportsOscillation
            ? '${summary.percentage} · 摆风${summary.oscillating ? '开' : '关'}'
            : '${summary.percentage}')
        : (summary.supportsOscillation
            ? '${summary.speedLabel} · 摆风${summary.oscillating ? '开' : '关'}'
            : summary.speedLabel);

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
                      color: _accent.withValues(alpha: on ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.wind_power_rounded,
                      size: 21,
                      color: on ? _accent : theme.colorScheme.outline,
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
                          '${areaLabel ?? '未分配房间'} · ${on ? summary.statusLabel : '点击开启'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: on
                                ? _accent
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关闭风扇' : '开启风扇',
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
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    on ? summary.mode : '已关闭',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: on ? null : theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    detail,
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

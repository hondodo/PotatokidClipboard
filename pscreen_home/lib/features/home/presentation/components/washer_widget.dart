import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';

/// 洗衣机快捷卡片：状态 / 剩余时间 + 电源键。
///
/// 主开关使用 `WasherSummary.powerEntityId`（真正的 `switch.*_on`），
/// 不再依赖组内排序，避免把「提示音 / 静音」当成主开关。
/// 点击卡片其余区域进入洗衣机详情。
class WasherWidget extends StatelessWidget {
  const WasherWidget({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    this.onOpenDetail,
  });

  final WasherSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final Color accent = on ? _accent : theme.colorScheme.outline;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.local_laundry_service_rounded,
                      size: 21,
                      color: accent,
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
                          summary.statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: summary.hasFault
                                ? theme.colorScheme.error
                                : (on ? _accent : theme.colorScheme.outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关闭洗衣机' : '开启洗衣机',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isToggling ? null : onToggle,
                    icon: isToggling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : Icon(
                            Icons.power_settings_new_rounded,
                            size: 20,
                            color: accent,
                          ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  if (summary.energyKwh != null)
                    _MiniStat(
                      icon: Icons.bolt_rounded,
                      text: '${_format(summary.energyKwh)} kWh',
                    ),
                  if (summary.waterConsumption != null) ...<Widget>[
                    const SizedBox(width: 12),
                    _MiniStat(
                      icon: Icons.water_drop_outlined,
                      text: _format(summary.waterConsumption),
                    ),
                  ],
                  if (summary.washedTimes != null) ...<Widget>[
                    const SizedBox(width: 12),
                    _MiniStat(
                      icon: Icons.check_circle_outline_rounded,
                      text: '${summary.washedTimes} 次',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _format(double? value) {
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

/// 卡片底部的小统计项。
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

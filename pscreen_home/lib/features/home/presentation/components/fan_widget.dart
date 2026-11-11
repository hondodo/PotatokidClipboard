import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/device_type_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/power_toggle_button.dart';

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
    this.showAreaInTitle = false,
    this.onOpenDetail,
  });

  final FanSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final bool showAreaInTitle;
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
                  DeviceTypeIcon(
                    color: _accent,
                    icon: Icons.wind_power_rounded,
                    on: on,
                    size: 54,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
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
                  PowerToggleButton(
                    on: on,
                    isToggling: isToggling,
                    color: _accent,
                    onPressed: isToggling ? null : onToggle,
                    tooltip: on ? '关闭风扇' : '开启风扇',
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

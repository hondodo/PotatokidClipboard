import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';
import 'package:pscreen_home/features/home/presentation/components/device_type_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/power_toggle_button.dart';

/// 空调快捷卡片：当前温度 + 目标温度加减。
///
/// 点卡片其余区域进入设备详情；没有设备详情路由时退化为开关。
/// 加减按钮直接下发 `climate.set_temperature`，界面用乐观更新即时反馈。
class ClimateWidget extends StatelessWidget {
  const ClimateWidget({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    required this.onIncrease,
    required this.onDecrease,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onOpenDetail,
    this.powerWatts,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final String? areaLabel;
  final bool showAreaInTitle;
  final VoidCallback? onOpenDetail;

  /// 实时功率（W），来自同设备电量传感器（如空调插座）；null 则不显示。
  final double? powerWatts;

  static const Color _accent = Color(0xFF5FD3C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final bool available = entity.isAvailable;
    final String target = formatTemperature(entity.targetTemperature);
    final String current = entity.currentTemperature == null
        ? ''
        : ' · ${formatTemperature(entity.currentTemperature)}°C';
    final String status = available
        ? '${on ? hvacModeLabel(entity.hvacMode) : '已关闭'}$current'
        : '不可用';
    // 实时功率跟在状态后（如「制冷 · 425 W · 卧室」），无传感器则不占位。
    final String power =
        powerWatts == null ? '' : ' · ${powerWatts!.round()} W';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: available && !isToggling
            ? (onOpenDetail ?? onToggle)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DeviceTypeIcon(
                    color: _accent,
                    icon: Icons.air_rounded,
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
                            title: entity.displayName,
                            areaLabel: areaLabel,
                            showArea: showAreaInTitle,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: available
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$status$power · ${areaLabel ?? '未分配房间'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: on && available
                                ? _accent
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 快捷开关：与灯卡一致，不必进详情就能开/关
                  PowerToggleButton(
                    on: on,
                    isToggling: isToggling,
                    color: _accent,
                    onPressed:
                        available && !isToggling ? onToggle : null,
                    tooltip: on ? '关闭空调' : '开启空调',
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  _StepButton(
                    icon: Icons.remove_rounded,
                    enabled: available,
                    onTap: onDecrease,
                  ),
                  Expanded(
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: target,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: available
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.outline,
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
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add_rounded,
                    enabled: available,
                    onTap: onIncrease,
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

/// 圆形加减按钮（独立水波纹，不触发外层卡片点击）。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

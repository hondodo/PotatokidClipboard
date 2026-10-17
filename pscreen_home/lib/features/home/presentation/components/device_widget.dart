import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 设备合并卡片：同一物理设备的多个可控实体聚合为一张卡。
///
/// 外层展示设备名 + 聚合状态 + 房间；主实体是支持调光的灯时，底部附带
/// 亮度滑条与百分比（与单灯卡片一致）。右侧电源键只切主实体，点击卡片
/// 其余区域进入设备详情页逐实体控制。
///
/// 仅用于多实体设备（[HaDeviceGroup.isMerged]）；
/// 单实体设备继续用 [LightWidget] / [ButtonWidget] / [ClimateWidget]。
class DeviceWidget extends StatelessWidget {
  const DeviceWidget({
    super.key,
    required this.group,
    required this.isToggling,
    required this.onTogglePrimary,
    required this.onOpenDetail,
    this.areaLabel,
    this.onBrightnessChanged,
  });

  final HaDeviceGroup group;

  /// 主实体指令执行中
  final bool isToggling;

  /// 快捷电源键：切换主实体开关
  final VoidCallback onTogglePrimary;

  /// 点击卡片：进入设备详情页
  final VoidCallback onOpenDetail;

  /// 所属房间展示名
  final String? areaLabel;

  /// 主实体亮度调整完成（0-100），主实体不支持调光时为 null
  final ValueChanged<int>? onBrightnessChanged;

  static const Color _lightAccent = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HaEntityStateModel primary = group.primary;
    final bool on = primary.isOn;
    final bool available = primary.isAvailable;
    final bool isLight = primary.isLight;
    final bool canDim = isLight &&
        primary.supportsBrightness &&
        available &&
        onBrightnessChanged != null;
    final Color accent = on
        ? (isLight ? _lightAccent : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            mainAxisAlignment: canDim
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: on ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: isToggling
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(
                            isLight
                                ? Icons.lightbulb_rounded
                                : Icons.devices_rounded,
                            color: accent,
                            size: 21,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: available
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodySmall,
                            children: <InlineSpan>[
                              TextSpan(
                                text: group.statusLabel,
                                style: TextStyle(color: accent),
                              ),
                              TextSpan(
                                text: ' · ${areaLabel ?? '未分配房间'}',
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (canDim)
                    Text(
                      '${primary.brightnessPercent ?? 0}%',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  // 快捷电源键：只切主实体；卡片其余区域进详情页
                  IconButton(
                    tooltip: '开关主控',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        available && !isToggling ? onTogglePrimary : null,
                    icon: isToggling
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(
                            Icons.power_settings_new_rounded,
                            color: accent,
                            size: 22,
                          ),
                  ),
                ],
              ),
              if (canDim) ...<Widget>[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GradientSlider(
                    value: (primary.brightnessPercent ?? 0).toDouble(),
                    min: 0,
                    max: 100,
                    colors: const <Color>[
                      Color(0xFFFF9E4A),
                      Color(0xFFFFC46B),
                    ],
                    height: 10,
                    thumbWidth: 4,
                    thumbHeight: 18,
                    onChangeEnd: (double value) =>
                        onBrightnessChanged?.call(value.round()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

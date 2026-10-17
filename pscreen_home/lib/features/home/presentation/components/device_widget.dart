import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';
import 'package:pscreen_home/features/home/presentation/components/ha_domain_icons.dart';

/// 设备合并卡片：同一物理设备的全部实体聚合为一张卡。
///
/// 形态随分组内容变化：
/// - 有可开关主实体：右侧电源键切主实体；主实体是灯时附带亮度滑条；
/// - 纯数据 / 动作设备：不显示电源键，仅展示聚合状态；
/// - 组内全部不可用：整体置灰、不可点击。
///
/// 点击卡片其余区域进入设备详情页逐实体查看 / 控制。
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

  /// 快捷电源键：切换主实体（无主实体时不显示电源键）
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
    final HaEntityStateModel? primary = group.primary;
    final bool available = !group.isUnavailable;
    final bool on = primary?.isOn ?? false;
    final String domain = primary?.domain ?? group.entities.first.domain;
    final bool isLight = domain == 'light';
    final bool canDim = primary != null &&
        primary.isLight &&
        primary.supportsBrightness &&
        primary.isAvailable &&
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
        onTap: available ? onOpenDetail : null,
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
                            HaDomainIcons.of(domain),
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
                  // 快捷电源键：仅当存在可开关主实体时显示
                  if (primary != null)
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

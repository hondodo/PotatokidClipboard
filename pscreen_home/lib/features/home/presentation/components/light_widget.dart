import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/device_type_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 灯光快捷卡片：开关 +（仅可调光灯）亮度滑条。
///
/// 卡片空白处点击切开关；底部渐变滑条拖动调整亮度（松手才下发，
/// 避免拖动过程刷屏）。
///
/// 重要：亮度滑条**只在实体真正支持调光**（`entity.supportsBrightness`，
/// 即 HA 的 color_mode 不只是 onoff）时才渲染。纯开关灯 / 指示灯没有调光
/// 能力，绝不显示滑条——否则会让老人误以为能调亮度，并可能误发调光指令。
class LightWidget extends StatelessWidget {
  const LightWidget({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onBrightnessChanged,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;
  final bool showAreaInTitle;

  /// 亮度调整完成（0-100）。仅当实体支持调光且本回调非空时滑条才出现。
  final ValueChanged<int>? onBrightnessChanged;

  static const Color _accent = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final bool available = entity.isAvailable;
    final bool canDim = available &&
        entity.supportsBrightness &&
        onBrightnessChanged != null;
    final int percent = entity.brightnessPercent ?? 0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: available && !isToggling ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  DeviceTypeIcon(
                    color: _accent,
                    icon: Icons.lightbulb_rounded,
                    on: on,
                    isToggling: isToggling,
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
                        const SizedBox(height: 3),
                        Text(
                          available
                              ? '${on ? '已开启' : '已关闭'} · ${areaLabel ?? '未分配房间'}'
                              : '不可用',
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
                  if (!isToggling)
                    Text(
                      available ? '$percent%' : '—',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on ? _accent : theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              // 仅真正可调光的灯才显示亮度滑条；指示灯 / 纯开关灯不显示。
              if (canDim)
                GradientSlider(
                  value: percent.toDouble(),
                  min: 0,
                  max: 100,
                  colors: const <Color>[
                    Color(0xFFFF9E4A),
                    Color(0xFFFFC46B),
                  ],
                  // 触屏无 hover，底轨必须常显且与卡片背景对比明显；
                  // 同时加粗到触屏友好的尺寸（原 10 / 4×18 太细小）。
                  trackColor: theme.colorScheme.outlineVariant,
                  height: 28,
                  thumbWidth: 12,
                  thumbHeight: 42,
                  enabled: canDim,
                  onChangeEnd: (double value) =>
                      onBrightnessChanged?.call(value.round()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

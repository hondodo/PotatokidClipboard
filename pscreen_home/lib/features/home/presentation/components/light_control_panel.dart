import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 灯光控制面板（设备详情页）：开关 + 亮度 + 色温 + 灯光效果。
///
/// 亮度 / 色温拖动时本地即时预览，松手才下发指令；效果点击立即下发。
/// 控件可见性完全由实体属性决定（supported_color_modes / effect_list /
/// 色温范围），纯开关灯只显示开关。
class LightControlPanel extends StatelessWidget {
  const LightControlPanel({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    required this.onBrightnessChanged,
    required this.onColorTemperatureChanged,
    required this.onEffectSelected,
    this.areaLabel,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<int> onBrightnessChanged;
  final ValueChanged<int> onColorTemperatureChanged;
  final ValueChanged<String> onEffectSelected;
  final String? areaLabel;

  static const Color _accent = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final bool available = entity.isAvailable;
    final int percent = entity.brightnessPercent ?? 0;
    final int kelvin = entity.colorTempKelvin ?? entity.minColorTempKelvin ?? 0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: isToggling
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        )
                      : Icon(
                          Icons.lightbulb_rounded,
                          color: on ? _accent : theme.colorScheme.outline,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entity.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        available
                            ? '${on ? '已开启' : '已关闭'} · ${areaLabel ?? '未分配房间'}'
                            : '设备不可用',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: on && available
                              ? _accent
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: on,
                  onChanged: available && !isToggling
                      ? (bool _) => onToggle()
                      : null,
                  activeThumbColor: _accent,
                ),
              ],
            ),
            if (entity.supportsBrightness) ...<Widget>[
              const SizedBox(height: 22),
              _SectionHeader(
                label: '亮度',
                value: available ? '$percent%' : '—',
                valueColor: on ? _accent : theme.colorScheme.outline,
              ),
              const SizedBox(height: 8),
              GradientSlider(
                value: percent.toDouble(),
                min: 0,
                max: 100,
                colors: const <Color>[
                  Color(0xFFFF9E4A),
                  Color(0xFFFFC46B),
                ],
                height: 16,
                thumbWidth: 6,
                thumbHeight: 28,
                enabled: available,
                onChangeEnd: (double value) =>
                    onBrightnessChanged(value.round()),
              ),
            ],
            if (entity.supportsColorTemperature) ...<Widget>[
              const SizedBox(height: 22),
              _SectionHeader(
                label: '色温',
                value: '$kelvin K',
                valueColor: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              GradientSlider(
                value: kelvin.toDouble(),
                min: entity.minColorTempKelvin!.toDouble(),
                max: entity.maxColorTempKelvin!.toDouble(),
                colors: const <Color>[
                  Color(0xFFFFA94D),
                  Color(0xFFFFE2B8),
                  Color(0xFFEAF2FF),
                  Color(0xFF9DC4FF),
                ],
                height: 16,
                thumbWidth: 6,
                thumbHeight: 28,
                enabled: available,
                onChangeEnd: (double value) =>
                    onColorTemperatureChanged(value.round()),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('暖光', style: theme.textTheme.labelSmall),
                  Text('冷光', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
            if (entity.supportsEffect) ...<Widget>[
              const SizedBox(height: 22),
              Text(
                '灯光效果',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entity.effectList
                    .map((String item) => ChoiceChip(
                          label: Text(item),
                          selected: entity.effect == item,
                          showCheckmark: false,
                          onSelected: available
                              ? (bool _) => onEffectSelected(item)
                              : null,
                        ))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 参数区块标题：左侧名称、右侧当前值。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

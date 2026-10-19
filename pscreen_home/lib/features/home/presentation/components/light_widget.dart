import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 灯光快捷卡片：开关 + 亮度滑条。
///
/// 卡片空白处点击切开关；底部渐变滑条拖动调整亮度（松手才下发，
/// 避免拖动过程刷屏）。关闭 / 不支持调光时滑条置灰。
class LightWidget extends StatelessWidget {
  const LightWidget({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.onBrightnessChanged,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;

  /// 亮度调整完成（0-100）
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: isToggling
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : Icon(
                            Icons.lightbulb_rounded,
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
                          entity.displayName,
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
                height: 16,
                thumbWidth: 6,
                thumbHeight: 28,
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

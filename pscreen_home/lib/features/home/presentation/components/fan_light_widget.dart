import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 风扇灯组合卡片：同一设备同时有灯 + 风扇时使用。
///
/// 卡片展示灯的亮度与风扇模式/档位，主电源键控制灯；风扇在详情页控制。
class FanLightWidget extends StatelessWidget {
  const FanLightWidget({
    super.key,
    required this.light,
    required this.fan,
    required this.isToggling,
    required this.onToggleLight,
    this.onOpenDetail,
  });

  final HaEntityStateModel light;
  final FanSummary fan;
  final bool isToggling;
  final VoidCallback onToggleLight;
  final VoidCallback? onOpenDetail;

  static const Color _lightAccent = Color(0xFFFFB74D);
  static const Color _fanAccent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool lightOn = light.isOn;
    final int percent = light.brightnessPercent ?? 0;
    final String fanText = fan.isOn
        ? '${fan.mode} ${fan.isContinuous ? fan.percentage : fan.speedLabel}'
        : '关';

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
                      color: _lightAccent.withValues(
                        alpha: lightOn ? 0.20 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.lightbulb_rounded,
                      size: 21,
                      color: lightOn
                          ? _lightAccent
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: lightOn ? '关灯' : '开灯',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isToggling ? null : onToggleLight,
                    icon: Icon(
                      Icons.power_settings_new_rounded,
                      size: 19,
                      color: lightOn
                          ? _lightAccent
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Text(
                    '灯 $percent%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: lightOn
                          ? _lightAccent
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.wind_power_rounded,
                    size: 15,
                    color: fan.isOn
                        ? _fanAccent
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      fanText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fan.isOn
                            ? _fanAccent
                            : theme.colorScheme.outline,
                      ),
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

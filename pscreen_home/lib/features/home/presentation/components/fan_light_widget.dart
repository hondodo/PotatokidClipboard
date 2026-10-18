import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 风扇灯总开关行：双图标 + 总开关，放在详情页第一行。
class FanLightMasterRow extends StatelessWidget {
  const FanLightMasterRow({
    super.key,
    required this.name,
    required this.master,
    required this.isToggling,
    required this.onToggle,
  });

  final String name;
  final HaEntityStateModel master;
  final bool isToggling;
  final VoidCallback onToggle;

  static const Color _lightAccent = Color(0xFFFFB74D);
  static const Color _fanAccent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = master.isOn;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _fanAccent.withValues(alpha: on ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.wind_power_rounded,
                size: 20,
                color: on ? _fanAccent : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _lightAccent.withValues(alpha: on ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.lightbulb_rounded,
                size: 20,
                color: on ? _lightAccent : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '总开关',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$name · ${on ? '已开启' : '已关闭'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: on ? _fanAccent : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: on,
              onChanged: isToggling ? null : (bool _) => onToggle(),
              activeThumbColor: _fanAccent,
            ),
          ],
        ),
      ),
    );
  }
}

/// 风扇灯组合卡片：同一设备同时有灯 + 风扇时使用。
///
/// 卡片展示灯的亮度与风扇模式/档位；右上角快捷开关控制总开关。
class FanLightWidget extends StatelessWidget {
  const FanLightWidget({
    super.key,
    required this.light,
    required this.fan,
    required this.isToggling,
    required this.onToggleMaster,
    this.areaLabel,
    this.onOpenDetail,
  });

  final HaEntityStateModel light;
  final FanSummary fan;
  final bool isToggling;
  final VoidCallback onToggleMaster;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _lightAccent = Color(0xFFFFB74D);
  static const Color _fanAccent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool lightOn = light.isOn;
    final bool masterOn = fan.masterOn;
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          fan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          areaLabel ?? '未分配房间',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: masterOn ? '关闭总开关' : '开启总开关',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isToggling ? null : onToggleMaster,
                    icon: Icon(
                      Icons.power_settings_new_rounded,
                      size: 19,
                      color: masterOn
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

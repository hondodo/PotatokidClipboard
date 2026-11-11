import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/device_type_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';
import 'package:pscreen_home/features/home/presentation/components/power_toggle_button.dart';

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
/// 卡片布局（自上而下）：
/// 1. 顶部：类型图标 + 名称 + 房间 + 右上角「总开关」大按钮；
/// 2. 中部：两个大号子开关「灯 / 风扇」（各自独立控制，明显可点）；
/// 3. 底部：灯的亮度滑条（**仅当灯真正支持调光**时显示，否则回退风扇状态文字）。
///
/// 注意：亮度滑条绝不显示在不支持调光的灯上（含指示灯），避免老人误以为
/// 能调亮度，并避免向不支持调光的实体误发调光指令。
class FanLightWidget extends StatelessWidget {
  const FanLightWidget({
    super.key,
    required this.light,
    required this.fan,
    required this.isTogglingMaster,
    required this.onToggleMaster,
    required this.isTogglingLight,
    required this.onToggleLight,
    required this.isTogglingFan,
    required this.onToggleFan,
    this.onBrightnessChanged,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onOpenDetail,
  });

  final HaEntityStateModel light;
  final FanSummary fan;
  final bool isTogglingMaster;
  final VoidCallback onToggleMaster;
  final bool isTogglingLight;
  final VoidCallback onToggleLight;
  final bool isTogglingFan;
  final VoidCallback onToggleFan;

  /// 灯亮度调整完成（0-100）。仅当灯支持调光且非空时滑条出现。
  final ValueChanged<int>? onBrightnessChanged;

  final String? areaLabel;
  final bool showAreaInTitle;
  final VoidCallback? onOpenDetail;

  static const Color _lightAccent = Color(0xFFFFB74D);
  static const Color _fanAccent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool lightOn = light.isOn;
    final bool fanOn = fan.isOn;
    final bool masterOn = fan.masterOn;
    final int percent = light.brightnessPercent ?? 0;
    final bool lightDimming = light.supportsBrightness;
    final String fanText = fan.isOn
        ? '${fan.mode} ${fan.isContinuous ? fan.percentage : fan.speedLabel}'
        : '关';
    final bool masterBusy = isTogglingMaster;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DeviceTypeIcon(
                    color: _lightAccent,
                    icon: Icons.lightbulb_rounded,
                    on: lightOn,
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
                            title: fan.name,
                            areaLabel: areaLabel,
                            showArea: showAreaInTitle,
                          ),
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
                  PowerToggleButton(
                    on: masterOn,
                    isToggling: masterBusy,
                    color: _lightAccent,
                    onPressed: onToggleMaster,
                    tooltip: masterOn ? '关闭总开关' : '开启总开关',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SubSwitch(
                      icon: Icons.lightbulb_rounded,
                      label: '灯',
                      on: lightOn,
                      accent: _lightAccent,
                      isToggling: isTogglingLight,
                      onPressed: masterBusy ? null : onToggleLight,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SubSwitch(
                      icon: Icons.wind_power_rounded,
                      label: '风扇',
                      on: fanOn,
                      accent: _fanAccent,
                      isToggling: isTogglingFan,
                      onPressed: masterBusy ? null : onToggleFan,
                    ),
                  ),
                ],
              ),
              if (lightDimming) ...<Widget>[
                const SizedBox(height: 12),
                GradientSlider(
                  value: percent.toDouble(),
                  min: 0,
                  max: 100,
                  colors: const <Color>[
                    Color(0xFFFF9E4A),
                    Color(0xFFFFC46B),
                  ],
                  trackColor: theme.colorScheme.outlineVariant,
                  height: 28,
                  thumbWidth: 12,
                  thumbHeight: 42,
                  enabled: lightOn && onBrightnessChanged != null,
                  onChangeEnd: (double value) =>
                      onBrightnessChanged?.call(value.round()),
                ),
              ] else ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.wind_power_rounded,
                      size: 16,
                      color: fanOn ? _fanAccent : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        fanText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fanOn
                              ? _fanAccent
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 风扇灯卡片下方的大号子开关（灯 / 风扇）。
///
/// 44dp 高圆角药丸按钮，开启态填充强调色、关闭态中性描边，
/// 图标 + 文字并用，墙面屏老人也能一眼识别、准确点按。
class _SubSwitch extends StatelessWidget {
  const _SubSwitch({
    required this.icon,
    required this.label,
    required this.on,
    required this.accent,
    required this.onPressed,
    this.isToggling = false,
  });

  final IconData icon;
  final String label;
  final bool on;
  final Color accent;
  final VoidCallback? onPressed;
  final bool isToggling;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color bg = on
        ? accent.withValues(alpha: 0.18)
        : theme.colorScheme.surfaceContainerLow;
    final Color border = on ? accent : theme.colorScheme.outlineVariant;
    final Color fg = on ? accent : theme.colorScheme.outline;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isToggling ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: bg,
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isToggling)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else
                Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';

/// 热水器快捷卡片：状态 / 当前水温 + 目标温度加减 + 电源键。
///
/// 点击卡片其余区域进入热水器详情；目标温度按 1℃ 步进。
class WaterHeaterWidget extends StatelessWidget {
  const WaterHeaterWidget({
    super.key,
    required this.entity,
    required this.statusLabel,
    required this.isToggling,
    required this.onToggle,
    required this.onIncrease,
    required this.onDecrease,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onOpenDetail,
    this.preheatAvailable = false,
    this.preheatOn = false,
    this.isPreheating = false,
    this.onPreheatToggle,
  });

  final HaEntityStateModel entity;
  final String statusLabel;
  final bool isToggling;
  final VoidCallback onToggle;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final String? areaLabel;
  final bool showAreaInTitle;
  final VoidCallback? onOpenDetail;

  /// 设备是否带「预热」开关（switch.*_hot_water_recirculation）。
  final bool preheatAvailable;

  /// 预热开关当前是否开启。
  final bool preheatOn;

  /// 预热指令是否下发中。
  final bool isPreheating;

  /// 切换预热；为空时按钮不可点。
  final VoidCallback? onPreheatToggle;

  static const Color _accent = Color(0xFFFF8A65);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final String target = formatTemperature(entity.targetTemperature);
    final double? current = entity.currentTemperature;
    final String status = <String>[
      areaLabel ?? '未分配房间',
      statusLabel,
      if (current != null) '${formatTemperature(current)}°C',
    ].join(' · ');

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
                      color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.shower_rounded,
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
                          cardTitle(
                            title: entity.displayName,
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
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: on ? _accent : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关闭热水器' : '开启热水器',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isToggling ? null : onToggle,
                    icon: isToggling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : Icon(
                            Icons.power_settings_new_rounded,
                            size: 20,
                            color: on ? _accent : theme.colorScheme.outline,
                          ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  _StepButton(icon: Icons.remove_rounded, onTap: onDecrease),
                  Expanded(
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: target,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
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
                  _StepButton(icon: Icons.add_rounded, onTap: onIncrease),
                  if (preheatAvailable) ...<Widget>[
                    const SizedBox(width: 2),
                    _PreheatButton(
                      on: preheatOn,
                      busy: isPreheating,
                      onTap: onPreheatToggle,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 18)),
      ),
    );
  }
}

/// 首页卡上的预热快捷按钮：关闭时显示「预热」，开启后显示「预热中」。
///
/// 固定宽度，避免开启/关闭切换时把中间的温度数字挤得左右跳动。
class _PreheatButton extends StatelessWidget {
  const _PreheatButton({
    required this.on,
    required this.busy,
    required this.onTap,
  });

  final bool on;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = on
        ? WaterHeaterWidget._accent
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: on ? '关闭预热' : '开启预热',
      child: SizedBox(
        width: 56,
        height: 30,
        child: TextButton(
          onPressed: busy ? null : onTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            backgroundColor: on
                ? WaterHeaterWidget._accent.withValues(alpha: 0.18)
                : null,
            foregroundColor: color,
            disabledForegroundColor: color.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Text(
                  on ? '预热中' : '预热',
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

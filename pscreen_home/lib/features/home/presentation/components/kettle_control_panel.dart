import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 电热水瓶控制面板：当前水温、内置模式、目标温度、保温/除氯/风冷、开始/停止。
///
/// 米家的扩展/自定义模式定义在云端，HA 只暴露 `mode_id`，面板只呈现内置
/// 三种模式与共用参数。
class KettleControlPanel extends StatelessWidget {
  const KettleControlPanel({
    super.key,
    required this.summary,
    required this.isBusy,
    this.onStart,
    this.onStop,
    this.onModeSelected,
    this.onTargetTemperatureChanged,
    this.onKeepWarmTemperatureChanged,
    this.onToggleKeepWarm,
    this.onToggleDechlorination,
    this.onToggleRapidCooling,
  });

  final KettleSummary summary;
  final bool isBusy;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final ValueChanged<String>? onModeSelected;
  final ValueChanged<double>? onTargetTemperatureChanged;
  final ValueChanged<double>? onKeepWarmTemperatureChanged;
  final VoidCallback? onToggleKeepWarm;
  final VoidCallback? onToggleDechlorination;
  final VoidCallback? onToggleRapidCooling;

  static const Color _accent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = summary.isActive;

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
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.emoji_food_beverage_rounded,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.status} · ${summary.mode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: active
                              ? _accent
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: active ? '停止加热' : '开始加热',
                  onPressed: isBusy
                      ? null
                      : (active ? onStop : onStart),
                  icon: Icon(
                    active
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
            if (summary.hasFault) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '故障：${summary.fault}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: _format(summary.temperature),
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                        TextSpan(
                          text: '°C',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前温度',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '模式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: summary.modes
                    .map((String mode) => ChoiceChip(
                          label: Text(mode),
                          selected: summary.mode == mode,
                          showCheckmark: false,
                          onSelected: (bool _) => onModeSelected?.call(mode),
                        ))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 18),
            _LabeledSlider(
              label: '设定温度',
              value: '${_format(summary.targetTemperature)}°C',
              slider: GradientSlider(
                value: summary.targetTemperature,
                min: summary.minTargetTemperature,
                max: summary.maxTargetTemperature,
                colors: const <Color>[
                  Color(0xFF42A5F5),
                  Color(0xFF4DD0C4),
                ],
                onChangeEnd: (double value) =>
                    onTargetTemperatureChanged?.call(value),
              ),
              min: '${_format(summary.minTargetTemperature)}°C',
              max: '${_format(summary.maxTargetTemperature)}°C',
            ),
            const SizedBox(height: 14),
            _SwitchRow(
              icon: Icons.thermostat_rounded,
              label: '保温',
              value: summary.keepWarmOn,
              onChanged: onToggleKeepWarm,
            ),
            if (summary.keepWarmOn)
              _LabeledSlider(
                label: '保温温度',
                value: '${_format(summary.keepWarmTemperature)}°C',
                slider: GradientSlider(
                  value: summary.keepWarmTemperature,
                  min: summary.minKeepWarmTemperature,
                  max: summary.maxKeepWarmTemperature,
                  colors: const <Color>[
                    Color(0xFFFFB74D),
                    Color(0xFFFF8A65),
                  ],
                  onChangeEnd: (double value) =>
                      onKeepWarmTemperatureChanged?.call(value),
                ),
                min: '${_format(summary.minKeepWarmTemperature)}°C',
                max: '${_format(summary.maxKeepWarmTemperature)}°C',
              ),
            _SwitchRow(
              icon: Icons.bubble_chart_rounded,
              label: '除氯',
              value: summary.dechlorinationOn,
              onChanged: onToggleDechlorination,
            ),
            _SwitchRow(
              icon: Icons.air_rounded,
              label: '风冷',
              value: summary.rapidCoolingOn,
              onChanged: onToggleRapidCooling,
            ),
            if (summary.lockMode != null) ...<Widget>[
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '童锁：${summary.childLocked ? '已上锁' : '未上锁'} · '
                      '${summary.lockMode}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.slider,
    required this.min,
    required this.max,
  });

  final String label;
  final String value;
  final Widget slider;
  final String min;
  final String max;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        slider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(min, style: theme.textTheme.labelSmall),
            Text(max, style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Switch(
              value: value,
              onChanged: onChanged == null ? null : (bool _) => onChanged!(),
              activeThumbColor: const Color(0xFF4DD0C4),
            ),
          ],
        ),
      ),
    );
  }
}

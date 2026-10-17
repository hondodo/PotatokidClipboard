import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 热水器控制面板（设备详情页）：目标温度、洗浴模式、预热 / 定时预热。
///
/// 目标温度来自 `water_heater.temperature`（35-65℃），模式来自
/// `operation_list`；预热开关是设备下的 `switch.*_hot_water_recirculation`。
class WaterHeaterControlPanel extends StatelessWidget {
  const WaterHeaterControlPanel({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    required this.onTemperatureChanged,
    required this.onModeSelected,
    this.onPreheatToggle,
    this.onTimerPreheatToggle,
  });

  final WaterHeaterSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onModeSelected;
  final VoidCallback? onPreheatToggle;
  final VoidCallback? onTimerPreheatToggle;

  static const Color _accent = Color(0xFFFF8A65);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final double target =
        summary.targetTemperature ?? summary.minTemperature;
    final double current = summary.currentTemperature ?? 0;

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
                  child: Icon(
                    Icons.shower_rounded,
                    color: on ? _accent : theme.colorScheme.outline,
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
                        '${summary.statusLabel} · ${summary.mode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: on
                              ? _accent
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: on,
                  onChanged: isToggling ? null : (bool _) => onToggle(),
                  activeThumbColor: _accent,
                ),
              ],
            ),
            if (summary.hasFault) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '故障代码：${summary.fault}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Center(
              child: Column(
                children: <Widget>[
                  Text(
                    '目标温度 · ${summary.mode}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: formatTemperature(target),
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
                  const SizedBox(height: 2),
                  Text(
                    summary.statusLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: on ? _accent : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _TempStepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => onTemperatureChanged(target - summary.targetStep),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      GradientSlider(
                        value: target,
                        min: summary.minTemperature,
                        max: summary.maxTemperature,
                        colors: const <Color>[
                          Color(0xFF42A5F5),
                          Color(0xFF90CAF9),
                        ],
                        height: 16,
                        thumbWidth: 6,
                        thumbHeight: 28,
                        onChangeEnd: (double value) =>
                            onTemperatureChanged(value),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            '${formatTemperature(summary.minTemperature)}°C',
                            style: theme.textTheme.labelSmall,
                          ),
                          Text(
                            '${formatTemperature(summary.maxTemperature)}°C',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _TempStepButton(
                  icon: Icons.add_rounded,
                  onTap: () => onTemperatureChanged(target + summary.targetStep),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                _InfoItem(
                  label: '当前水温',
                  value: current > 0 ? '${formatTemperature(current)}°C' : '—',
                ),
                _InfoItem(
                  label: '进水温度',
                  value: summary.inletTemperature == null
                      ? '—'
                      : '${formatTemperature(summary.inletTemperature)}°C',
                ),
                _InfoItem(
                  label: '水流量',
                  value: summary.flowRate == null
                      ? '—'
                      : '${formatTemperature(summary.flowRate)} L/min',
                ),
              ],
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '洗浴模式',
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
                          onSelected: (bool _) => onModeSelected(mode),
                        ))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 18),
            _SwitchRow(
              icon: Icons.local_fire_department_rounded,
              label: '预热',
              value: summary.preheatOn,
              onChanged:
                  summary.preheatEntityId == null ? null : onPreheatToggle,
            ),
            if (summary.timerPreheatEntityId != null)
              _SwitchRow(
                icon: Icons.schedule_rounded,
                label: '定时预热',
                value: summary.timerPreheatOn,
                onChanged: onTimerPreheatToggle,
              ),
          ],
        ),
      ),
    );
  }
}

class _TempStepButton extends StatelessWidget {
  const _TempStepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
              activeThumbColor: const Color(0xFFFF8A65),
            ),
          ],
        ),
      ),
    );
  }
}

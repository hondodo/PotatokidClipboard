import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';

/// 空调控制面板（设备详情页）：当前温湿度、圆形目标温度盘、模式/风速/摆风。
///
/// 所有档位来自实体属性（hvac_modes / fan_modes / swing_modes），
/// 设备不支持的项目自动隐藏；温度按 target_temp_step 步进。
class ClimateControlPanel extends StatelessWidget {
  const ClimateControlPanel({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    required this.onTemperatureChanged,
    required this.onHvacModeSelected,
    required this.onFanModeSelected,
    required this.onSwingModeSelected,
    this.areaLabel,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onHvacModeSelected;
  final ValueChanged<String> onFanModeSelected;
  final ValueChanged<String> onSwingModeSelected;
  final String? areaLabel;

  static const Color _accent = Color(0xFF5FD3C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final bool available = entity.isAvailable;
    final double target =
        entity.targetTemperature ?? entity.minTargetTemperature;
    final double current = entity.currentTemperature ?? target;
    final double min = entity.minTargetTemperature;
    final double max = entity.maxTargetTemperature;
    final double span = (max - min) == 0 ? 1 : max - min;
    final double targetFraction =
        ((target - min) / span).clamp(0.0, 1.0);
    final double currentFraction =
        ((current - min) / span).clamp(0.0, 1.0);

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
                          Icons.air_rounded,
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
                            ? '${on ? hvacModeLabel(entity.hvacMode) : '已关闭'} · ${areaLabel ?? '未分配房间'}'
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
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Stat(
                    label: '当前温度',
                    value: entity.currentTemperature == null
                        ? '—'
                        : '${formatTemperature(entity.currentTemperature)}${entity.temperatureUnit}',
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _Stat(
                    label: '当前湿度',
                    value: entity.currentHumidity == null
                        ? '—'
                        : '${entity.currentHumidity}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ClimateDialPainter(
                          fraction: targetFraction,
                          currentFraction: entity.currentTemperature == null
                              ? null
                              : currentFraction,
                          accent: _accent,
                          track: theme.colorScheme.surfaceContainerHighest,
                          handleFill: theme.colorScheme.surfaceContainerHigh,
                          marker: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            on
                                ? hvacModeLabel(entity.hvacMode)
                                : '关闭',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 4),
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
                                  text: entity.temperatureUnit,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '目标温度',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _TempStepButton(
                  icon: Icons.remove_rounded,
                  enabled: available,
                  onTap: () => _step(-1),
                ),
                const SizedBox(width: 28),
                _TempStepButton(
                  icon: Icons.add_rounded,
                  enabled: available,
                  onTap: () => _step(1),
                ),
              ],
            ),
            if (entity.hvacModes.any((String m) => m != 'off')) ...<Widget>[
              const SizedBox(height: 18),
              _SectionTitle(label: '模式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entity.hvacModes
                    .where((String m) => m != 'off')
                    .map((String mode) => ChoiceChip(
                          label: Text(hvacModeLabel(mode)),
                          selected: entity.isOn && entity.hvacMode == mode,
                          showCheckmark: false,
                          onSelected: available
                              ? (bool _) => onHvacModeSelected(mode)
                              : null,
                        ))
                    .toList(growable: false),
              ),
            ],
            if (entity.fanModes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              _SectionTitle(label: '风扇模式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entity.fanModes
                    .map((String mode) => ChoiceChip(
                          label: Text(mode),
                          selected: entity.fanMode == mode,
                          showCheckmark: false,
                          onSelected: available
                              ? (bool _) => onFanModeSelected(mode)
                              : null,
                        ))
                    .toList(growable: false),
              ),
            ],
            if (entity.swingModes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              _SectionTitle(label: '摆动模式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entity.swingModes
                    .map((String mode) => ChoiceChip(
                          label: Text(swingModeLabel(mode)),
                          selected: entity.swingMode == mode,
                          showCheckmark: false,
                          onSelected: available
                              ? (bool _) => onSwingModeSelected(mode)
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

  /// 按 target_temp_step 加减，并夹在设备温度范围内。
  void _step(int direction) {
    final double step = entity.targetTempStep;
    final double base = entity.targetTemperature ?? entity.minTargetTemperature;
    final double next = (base + direction * step)
        .clamp(entity.minTargetTemperature, entity.maxTargetTemperature)
        .toDouble();
    onTemperatureChanged(next);
  }
}

/// 温湿度统计项。
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 区块标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// 温度加减圆钮。
class _TempStepButton extends StatelessWidget {
  const _TempStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 24,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

/// 270° 圆环：底轨 + 目标温度进度 + 当前温度标记 + 目标温度滑块。
class _ClimateDialPainter extends CustomPainter {
  const _ClimateDialPainter({
    required this.fraction,
    required this.currentFraction,
    required this.accent,
    required this.track,
    required this.handleFill,
    required this.marker,
  });

  final double fraction;
  final double? currentFraction;
  final Color accent;
  final Color track;
  final Color handleFill;
  final Color marker;

  static const double _start = math.pi * 3 / 4;
  static const double _sweep = math.pi * 3 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 14;
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - stroke) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, trackPaint);

    if (fraction > 0) {
      final Paint progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent;
      canvas.drawArc(rect, _start, _sweep * fraction, false, progressPaint);
    }

    final double? current = currentFraction;
    if (current != null) {
      final double angle = _start + _sweep * current;
      final Offset point = center +
          Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(point, 4, Paint()..color = marker);
    }

    final double handleAngle = _start + _sweep * fraction;
    final Offset handle =
        center + Offset(math.cos(handleAngle), math.sin(handleAngle)) * radius;
    canvas.drawCircle(handle, 11, Paint()..color = handleFill);
    canvas.drawCircle(handle, 7, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_ClimateDialPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.currentFraction != currentFraction ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track ||
      oldDelegate.handleFill != handleFill ||
      oldDelegate.marker != marker;
}

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';

/// 冰箱控制面板：三舱当前温度、模式、各舱目标温度。
class FridgeControlPanel extends StatelessWidget {
  const FridgeControlPanel({
    super.key,
    required this.summary,
    required this.onModeSelected,
    required this.onTargetChanged,
  });

  final FridgeSummary summary;
  final ValueChanged<String> onModeSelected;
  final void Function(String entityId, int temperature) onTargetChanged;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool warning = summary.hasWarning;

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
                    color: _accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.kitchen_rounded,
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
                        '${summary.statusLabel} · 运行中',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: warning
                              ? theme.colorScheme.error
                              : _accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '运行中',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.hasWarning) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(
                    summary.hasFault
                        ? Icons.error_outline_rounded
                        : Icons.door_front_door_outlined,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      summary.hasFault
                          ? '冰箱故障：${summary.fault}'
                          : '有门未关，请检查冰箱门',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: summary.zones
                  .map((FridgeZone zone) => Expanded(
                        child: Column(
                          children: <Widget>[
                            Text(
                              zone.name,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${zone.currentTemperature ?? '--'}°C',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '目标 ${zone.targetTemperature}°C',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(growable: false),
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                '冰箱模式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
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
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final FridgeZone zone in summary.zones)
              _ZoneRow(
                zone: zone,
                onChanged: (int value) =>
                    onTargetChanged(zone.targetEntityId, value),
              ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: <Widget>[
                _InfoItem(
                  icon: Icons.thermostat_rounded,
                  label: '环境',
                  value: summary.environmentTemperature == null
                      ? '—'
                      : '${summary.environmentTemperature}°C',
                ),
                _InfoItem(
                  icon: Icons.water_drop_outlined,
                  label: '湿度',
                  value: summary.environmentHumidity == null
                      ? '—'
                      : '${summary.environmentHumidity}%',
                ),
                _InfoItem(
                  icon: Icons.timer_outlined,
                  label: '运行',
                  value: summary.runtimeLabel,
                ),
                _InfoItem(
                  icon: Icons.door_front_door_outlined,
                  label: '开门',
                  value:
                      '冷藏 ${summary.refrigeratorOpenTimes ?? '—'} / 冷冻 ${summary.freezerOpenTimes ?? '—'}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '食材管理是米家云端数据，HA 未暴露食材列表；这里只控制温度与模式。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.zone, required this.onChanged});

  final FridgeZone zone;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canDecrease = zone.targetTemperature > zone.minTemperature;
    final bool canIncrease = zone.targetTemperature < zone.maxTemperature;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  zone.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${zone.minTemperature} ~ ${zone.maxTemperature}°C',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '${zone.name}温度 -',
            onPressed:
                canDecrease ? () => onChanged(zone.targetTemperature - 1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${zone.targetTemperature}°C',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: FridgeControlPanel._accent,
              ),
            ),
          ),
          IconButton(
            tooltip: '${zone.name}温度 +',
            onPressed:
                canIncrease ? () => onChanged(zone.targetTemperature + 1) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

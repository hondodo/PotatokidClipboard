import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';

/// 油烟机详情：电源、风量、延时关机、灯光、巡航、假日、干洗。
class RangeHoodControlPanel extends StatelessWidget {
  const RangeHoodControlPanel({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    required this.onFanLevelSelected,
    required this.onDelayToggle,
    required this.onDelayMinutesChanged,
    required this.onLightToggle,
    required this.onCruiseToggle,
    required this.onHolidayToggle,
    required this.onDryCleaningStart,
    required this.onDryCleaningStop,
  });

  final RangeHoodSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<String> onFanLevelSelected;
  final VoidCallback? onDelayToggle;
  final ValueChanged<int> onDelayMinutesChanged;
  final VoidCallback? onLightToggle;
  final VoidCallback? onCruiseToggle;
  final VoidCallback? onHolidayToggle;
  final VoidCallback? onDryCleaningStart;
  final VoidCallback? onDryCleaningStop;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;

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
                  child: const Icon(Icons.air_rounded, color: _accent),
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
                        summary.statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: summary.hasFault
                              ? theme.colorScheme.error
                              : (on ? _accent : theme.colorScheme.outline),
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
            const SizedBox(height: 18),
            Text(
              '挡位',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summary.fanLevels
                  .map((String level) => ChoiceChip(
                        label: Text(level),
                        selected: summary.fanLevel == level,
                        showCheckmark: false,
                        onSelected:
                            on ? (bool _) => onFanLevelSelected(level) : null,
                      ))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _SwitchRow(
              label: '延时关机',
              value: summary.delayOn,
              onTap: onDelayToggle,
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 4),
                Text(
                  '延时时长',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '延时 -',
                  onPressed: summary.delayMinutes > 1
                      ? () =>
                          onDelayMinutesChanged(summary.delayMinutes - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Text(
                  '${summary.delayMinutes} 分钟',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: '延时 +',
                  onPressed: summary.delayMinutes < 7
                      ? () =>
                          onDelayMinutesChanged(summary.delayMinutes + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            _SwitchRow(
              label: '照明灯光',
              value: summary.lightOn,
              onTap: onLightToggle,
            ),
            _SwitchRow(
              label: '自动巡航',
              value: summary.cruiseOn,
              onTap: onCruiseToggle,
            ),
            _SwitchRow(
              label: '假日模式',
              value: summary.holidayOn,
              onTap: onHolidayToggle,
            ),
            const Divider(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '智能干洗 · ${summary.dryCleaningStatus ?? '未知'}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: summary.isDryCleaning
                      ? onDryCleaningStop
                      : onDryCleaningStart,
                  child: Text(summary.isDryCleaning ? '停止' : '启动'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        Switch(
          value: value,
          onChanged: onTap == null ? null : (bool _) => onTap!(),
          activeThumbColor: RangeHoodControlPanel._accent,
        ),
      ],
    );
  }
}

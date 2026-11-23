import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';

/// 油烟机高级设置：烟灶联动、手势、清洁提醒、假日周期、定时干洗、灯光联动。
class RangeHoodAdvancedSettings extends StatelessWidget {
  const RangeHoodAdvancedSettings({
    super.key,
    required this.summary,
    required this.onToggle,
    required this.onNumber,
    required this.onSelect,
  });

  final RangeHoodSummary summary;
  final ValueChanged<String> onToggle;
  final void Function(String entityId, int value) onNumber;
  final void Function(String entityId, String option) onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '高级设置',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _SwitchSetting(
          label: '烟灶联动',
          value: summary.stoveLinked,
          entityId: summary.stoveLinkEntityId,
          onToggle: onToggle,
        ),
        _SwitchSetting(
          label: '启用手势',
          value: summary.gesturesOn,
          entityId: summary.gesturesEntityId,
          onToggle: onToggle,
        ),
        _SwitchSetting(
          label: '定时清洁提醒',
          value: summary.cleanReminderOn,
          entityId: summary.cleanReminderEntityId,
          onToggle: onToggle,
        ),
        _NumberSetting(
          label: '清洁提醒时长',
          value: '${summary.cleanReminderHours} 小时',
          current: summary.cleanReminderHours,
          min: 20,
          max: 50,
          step: 10,
          entityId: summary.cleanReminderTimeEntityId,
          onNumber: onNumber,
        ),
        _SwitchSetting(
          label: '定时智能干洗',
          value: summary.dryCleaningTimingOn,
          entityId: summary.dryCleaningTimingEntityId,
          onToggle: onToggle,
        ),
        _SwitchSetting(
          label: '开机时开灯',
          value: summary.powerOnLight,
          entityId: summary.powerOnLightEntityId,
          onToggle: onToggle,
        ),
        _SwitchSetting(
          label: '关机时关灯',
          value: summary.powerOffLight,
          entityId: summary.powerOffLightEntityId,
          onToggle: onToggle,
        ),
        _NumberSetting(
          label: '灶台连续工作提醒',
          value: summary.stoveWorkReminderMinutes == 0
              ? '关闭'
              : '${summary.stoveWorkReminderMinutes} 分钟',
          current: summary.stoveWorkReminderMinutes,
          min: 0,
          max: 480,
          step: 30,
          entityId: summary.stoveWorkReminderEntityId,
          onNumber: onNumber,
        ),
        if (summary.holidayCycles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '假日换气周期',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                DropdownButton<String>(
                  value: summary.holidayCycle.isEmpty
                      ? null
                      : summary.holidayCycle,
                  underline: const SizedBox.shrink(),
                  items: summary.holidayCycles
                      .map((String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text('$value 天'),
                          ))
                      .toList(growable: false),
                  onChanged: summary.holidayCycleEntityId == null
                      ? null
                      : (String? value) {
                          if (value == null) return;
                          onSelect(summary.holidayCycleEntityId!, value);
                        },
                ),
              ],
            ),
          ),
        _NumberSetting(
          label: '假日每次持续',
          value: '${summary.holidayDurationMinutes} 分钟',
          current: summary.holidayDurationMinutes,
          min: 3,
          max: 9,
          step: 1,
          entityId: summary.holidayDurationEntityId,
          onNumber: onNumber,
        ),
        _NumberSetting(
          label: '假日开启时间',
          value: summary.holidayStartLabel,
          current: summary.holidayStartMinutes,
          min: 0,
          max: 1439,
          step: 1,
          entityId: summary.holidayStartEntityId,
          onNumber: onNumber,
        ),
      ],
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.label,
    required this.value,
    required this.entityId,
    required this.onToggle,
  });

  final String label;
  final bool value;
  final String? entityId;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Switch(
          value: value,
          onChanged: entityId == null ? null : (bool _) => onToggle(entityId!),
          activeThumbColor: const Color(0xFF64B5F6),
        ),
      ],
    );
  }
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.label,
    required this.value,
    required this.current,
    required this.min,
    required this.max,
    required this.step,
    required this.entityId,
    required this.onNumber,
  });

  final String label;
  final String value;
  final int current;
  final int min;
  final int max;
  final int step;
  final String? entityId;
  final void Function(String entityId, int value) onNumber;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = entityId != null;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          tooltip: '$label -',
          onPressed: enabled && current > min
              ? () => onNumber(entityId!, current - step)
              : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            color: enabled
                ? const Color(0xFF64B5F6)
                : theme.colorScheme.outline,
          ),
        ),
        IconButton(
          tooltip: '$label +',
          onPressed: enabled && current < max
              ? () => onNumber(entityId!, current + step)
              : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}

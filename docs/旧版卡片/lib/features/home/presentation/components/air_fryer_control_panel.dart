import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/air_fryer_summary.dart';

/// 空气炸锅详情：模式、温度、时间、启动/暂停/继续/停止、保温。
class AirFryerControlPanel extends StatelessWidget {
  const AirFryerControlPanel({
    super.key,
    required this.summary,
    required this.onModeSelected,
    required this.onTemperatureChanged,
    required this.onTimeChanged,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onAutoKeepWarm,
    required this.onCurrentKeepWarm,
  });

  final AirFryerSummary summary;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<int> onTemperatureChanged;
  final ValueChanged<int> onTimeChanged;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final VoidCallback? onAutoKeepWarm;
  final VoidCallback? onCurrentKeepWarm;

  static const Color _accent = Color(0xFFFF8A65);

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
                    Icons.bakery_dining_rounded,
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
                        summary.statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: summary.hasFault
                              ? theme.colorScheme.error
                              : (active
                                  ? _accent
                                  : theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '模式',
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
                          onSelected: active
                              ? null
                              : (bool _) => onModeSelected(mode),
                        ))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 16),
            _ValueRow(
              label: '温度',
              value: '${summary.temperature}°C',
              min: summary.minTemperature,
              max: summary.maxTemperature,
              step: summary.temperatureStep,
              enabled: !active,
              onChanged: onTemperatureChanged,
              current: summary.temperature,
            ),
            const SizedBox(height: 10),
            _ValueRow(
              label: '时间',
              value: '${summary.minutes} 分钟',
              min: summary.minMinutes,
              max: summary.maxMinutes,
              step: 1,
              enabled: !active,
              onChanged: onTimeChanged,
              current: summary.minutes,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (!active)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('开始烹饪'),
                    ),
                  )
                else ...<Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text('暂停'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('继续'),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: active ? onStop : null,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('停止'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _KeepWarm(
                    label: '自动保温',
                    value: summary.autoKeepWarm,
                    onTap: onAutoKeepWarm,
                  ),
                ),
                Expanded(
                  child: _KeepWarm(
                    label: '当前保温',
                    value: summary.currentKeepWarm,
                    onTap: onCurrentKeepWarm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.current,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final int min;
  final int max;
  final int step;
  final int current;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        IconButton(
          tooltip: '$label -',
          onPressed: enabled && current > min
              ? () => onChanged(current - step)
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: enabled
                  ? AirFryerControlPanel._accent
                  : theme.colorScheme.outline,
            ),
          ),
        ),
        IconButton(
          tooltip: '$label +',
          onPressed: enabled && current < max
              ? () => onChanged(current + step)
              : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _KeepWarm extends StatelessWidget {
  const _KeepWarm({
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
        Text(label, style: theme.textTheme.bodySmall),
        Switch(
          value: value,
          onChanged: onTap == null ? null : (bool _) => onTap!(),
          activeThumbColor: AirFryerControlPanel._accent,
        ),
      ],
    );
  }
}

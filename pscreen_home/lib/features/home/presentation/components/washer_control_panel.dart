import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';

/// 洗衣机控制面板（设备详情页）：状态、累计统计、快捷模式、启动/暂停/停止。
///
/// 米家洗衣机在 HA 里是 switch/select/sensor/button 的组合，本面板
/// 通过 [WasherSummary] 找到对应实体；缺失的项目自动隐藏。
class WasherControlPanel extends StatelessWidget {
  const WasherControlPanel({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    required this.onModeSelected,
    this.onStart,
    this.onPause,
    this.onStop,
  });

  final WasherSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<String> onModeSelected;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onStop;

  static const Color _accent = Color(0xFF64B5F6);
  static const List<String> _quickModes = <String>[
    '智能洗',
    '快速洗',
    '单烘干',
    '轻干洗',
    '随心洗烘',
    '筒清洁',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final bool running = summary.isRunning;
    final List<String> quick = _quickModes
        .where(summary.modes.contains)
        .toList(growable: true);
    if (quick.isEmpty) {
      quick.addAll(summary.modes.take(6));
    }

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
                    Icons.local_laundry_service_rounded,
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
                        summary.hasFault
                            ? '设备故障'
                            : '当前模式：${summary.mode ?? summary.status}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: summary.hasFault
                              ? theme.colorScheme.error
                              : (on
                                  ? _accent
                                  : theme.colorScheme.outline),
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
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          summary.status,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subStatus(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: summary.isRunning
                                ? _accent
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (summary.hasFault)
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                ],
              ),
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
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatBox(
                    label: '累计用电',
                    value: _format(summary.energyKwh),
                    unit: 'kWh',
                  ),
                ),
                Expanded(
                  child: _StatBox(
                    label: '累计用水',
                    value: _format(summary.waterConsumption),
                    unit: '',
                    tooltip: 'HA 的耗水量传感器未提供单位',
                  ),
                ),
                Expanded(
                  child: _StatBox(
                    label: '累计洗涤',
                    value: summary.washedTimes?.toString() ?? '—',
                    unit: '次',
                  ),
                ),
              ],
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '快捷模式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String mode in quick)
                    ChoiceChip(
                      label: Text(mode),
                      selected: summary.mode == mode,
                      showCheckmark: false,
                      onSelected: (bool _) => onModeSelected(mode),
                    ),
                  if (summary.modes.length > quick.length)
                    ActionChip(
                      avatar: const Icon(Icons.more_horiz_rounded, size: 18),
                      label: const Text('更多'),
                      onPressed: () => _showAllModes(context),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      onStart != null && on && !running ? onStart : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('启动'),
                ),
                OutlinedButton.icon(
                  onPressed: onPause != null && running ? onPause : null,
                  icon: const Icon(Icons.pause_rounded, size: 20),
                  label: const Text('暂停'),
                ),
                OutlinedButton.icon(
                  onPressed: onStop != null && running ? onStop : null,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text('停止'),
                ),
              ],
            ),
            if (summary.doorState != null) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.sensor_door_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '门状态：${summary.doorState}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
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

  String _subStatus() {
    if (summary.hasFault) return '请查看故障代码';
    if (summary.isRunning) {
      final int? left = summary.remainingMinutes;
      return left == null
          ? summary.runStatus
          : '${summary.runStatus} · 剩余 $left 分钟';
    }
    if (!summary.isOn) return '设备已关机，开启后可启动洗涤';
    return '待机中';
  }

  void _showAllModes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: summary.modes.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final String mode = summary.modes[index];
              return ListTile(
                title: Text(mode),
                trailing: summary.mode == mode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onModeSelected(mode);
                },
              );
            },
          ),
        );
      },
    );
  }

  static String _format(double? value) {
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

/// 统计项。
class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
    this.tooltip,
  });

  final String label;
  final String value;
  final String unit;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}

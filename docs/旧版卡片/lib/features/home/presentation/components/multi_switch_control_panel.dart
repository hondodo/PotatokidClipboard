import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';

/// 双开开关面板：两路按键独立开关 + 全开 / 全关。
class MultiSwitchControlPanel extends StatelessWidget {
  const MultiSwitchControlPanel({
    super.key,
    required this.summary,
    required this.togglingIds,
    required this.onToggleGang,
    required this.onAllOn,
    required this.onAllOff,
  });

  final MultiSwitchSummary summary;
  final Set<String> togglingIds;
  final ValueChanged<String> onToggleGang;
  final VoidCallback onAllOn;
  final VoidCallback onAllOff;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
                    Icons.toggle_on_rounded,
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
                          color: summary.isAnyOn
                              ? _accent
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final SwitchGang gang in summary.gangs) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    gang.isOn
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    color: gang.isOn
                        ? _accent
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      gang.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: gang.isOn,
                    onChanged: togglingIds.contains(gang.entityId)
                        ? null
                        : (bool _) => onToggleGang(gang.entityId),
                    activeThumbColor: _accent,
                  ),
                ],
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAllOn,
                    icon: const Icon(Icons.power_settings_new_rounded,
                        size: 18),
                    label: const Text('全开'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAllOff,
                    icon: const Icon(Icons.power_off_rounded, size: 18),
                    label: const Text('全关'),
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

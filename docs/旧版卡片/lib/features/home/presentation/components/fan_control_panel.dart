import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 风扇控制面板（设备详情页）：模式、风速、左右摆风、延时关闭。
///
/// 普通风扇按 percentage_step 走三挡；风扇灯（step=1）走无级调速。
/// 数据来自 `fan.*` 主实体与延时 number（`_off_delay_time_p_2_10` /
/// `_delay_time_p_6_2`），延时上限取 number 的 max 属性。
class FanControlPanel extends StatefulWidget {
  const FanControlPanel({
    super.key,
    required this.summary,
    required this.isToggling,
    required this.onToggle,
    required this.onModeSelected,
    required this.onSpeedSelected,
    required this.onPercentageChanged,
    required this.onOscillatingChanged,
    required this.onDelayChanged,
  });

  final FanSummary summary;
  final bool isToggling;
  final VoidCallback onToggle;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<int> onSpeedSelected;
  final ValueChanged<int> onPercentageChanged;
  final ValueChanged<bool> onOscillatingChanged;
  final ValueChanged<int> onDelayChanged;

  @override
  State<FanControlPanel> createState() => _FanControlPanelState();
}

class _FanControlPanelState extends State<FanControlPanel> {
  static const Color _accent = Color(0xFF4DD0C4);

  late int _delay = widget.summary.delayMinutes ?? 0;

  @override
  void didUpdateWidget(FanControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int next = widget.summary.delayMinutes ?? 0;
    if (next != (oldWidget.summary.delayMinutes ?? 0)) {
      _delay = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FanSummary summary = widget.summary;
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
                    color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.wind_power_rounded,
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
                        on
                            ? '${summary.mode} · ${summary.speedLabel}'
                            : '已关闭',
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
                  onChanged: widget.isToggling
                      ? null
                      : (bool _) => widget.onToggle(),
                  activeThumbColor: _accent,
                ),
              ],
            ),
            if (summary.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              _SectionTitle(title: '模式'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: summary.modes
                    .map((String mode) => ChoiceChip(
                          label: Text(mode),
                          selected: summary.mode == mode,
                          showCheckmark: false,
                          onSelected: on
                              ? (bool _) =>
                                  widget.onModeSelected(mode)
                              : null,
                        ))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 18),
            _SectionTitle(
              title: summary.isContinuous ? '无级调速' : '风机档位 | 三挡',
              trailing: on ? summary.speedLabel : null,
            ),
            const SizedBox(height: 10),
            if (summary.isContinuous)
              GradientSlider(
                value: summary.percentage.toDouble(),
                min: 1,
                max: 100,
                colors: const <Color>[
                  Color(0xFF42A5F5),
                  _accent,
                ],
                enabled: on,
                onChangeEnd: on
                    ? (double value) =>
                        widget.onPercentageChanged(value.round())
                    : null,
              )
            else
              Row(
                children: <Widget>[
                  for (int level = 1; level <= 3; level++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: level == 3 ? 0 : 10,
                        ),
                        child: _SpeedButton(
                          level: level,
                          selected: summary.speedLevel == level,
                          enabled: on,
                          onTap: () => widget.onSpeedSelected(level),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (summary.supportsOscillation)
              _SwitchRow(
                icon: Icons.swap_horiz_rounded,
                label: '左右摆风',
                value: summary.oscillating,
                onChanged: on
                    ? widget.onOscillatingChanged
                    : null,
              ),
            if (summary.hasDelay) ...<Widget>[
              const SizedBox(height: 10),
              _SectionTitle(
                title: '延时关闭',
                trailing: _delayLabel(_delay),
              ),
              const SizedBox(height: 8),
              GradientSlider(
                value: _delay.toDouble(),
                min: 0,
                max: summary.delayMaxMinutes.toDouble(),
                colors: const <Color>[
                  Color(0xFF42A5F5),
                  _accent,
                ],
                enabled: on,
                onChanged: on
                    ? (double value) {
                        setState(() => _delay = value.round());
                      }
                    : null,
                onChangeEnd: on
                    ? (double value) {
                        final int minutes = value.round();
                        setState(() => _delay = minutes);
                        widget.onDelayChanged(minutes);
                      }
                    : null,
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Text('0', style: theme.textTheme.labelSmall),
                  const Spacer(),
                  Text(
                    _delayLabel(summary.delayMaxMinutes),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _delayLabel(int minutes) {
    if (minutes <= 0) return '关闭';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    if (hours == 0) return '$rest分钟';
    if (rest == 0) return '$hours小时';
    return '$hours小时$rest分钟';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _FanControlPanelState._accent,
            ),
          ),
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int level;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = _FanControlPanelState._accent;
    final Color background = selected
        ? accent
        : theme.colorScheme.surfaceContainerHighest;
    final Color foreground = selected
        ? theme.colorScheme.onPrimary
        : (enabled ? theme.colorScheme.onSurface : theme.colorScheme.outline);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: Column(
        children: <Widget>[
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '$level',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            switch (level) {
              1 => '一挡',
              2 => '二挡',
              _ => '三挡',
            },
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? accent : theme.colorScheme.outline,
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
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _FanControlPanelState._accent,
        ),
      ],
    );
  }
}

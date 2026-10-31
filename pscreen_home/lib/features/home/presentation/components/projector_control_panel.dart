import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

/// 投影仪控制面板：开关机、应用、输入源、音量、亮度、静音、播放控制。
class ProjectorControlPanel extends StatelessWidget {
  const ProjectorControlPanel({
    super.key,
    required this.summary,
    required this.isBusy,
    required this.onPower,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onInputSelected,
    required this.onMuteToggle,
    required this.onOpenApp,
    required this.onButtonPressed,
    this.onOpenRemote,
  });

  final ProjectorSummary summary;
  final bool isBusy;
  final VoidCallback onPower;
  final ValueChanged<int> onVolumeChanged;
  final ValueChanged<int> onBrightnessChanged;
  final ValueChanged<String> onInputSelected;
  final VoidCallback onMuteToggle;
  final ValueChanged<String> onOpenApp;
  final ValueChanged<String> onButtonPressed;
  final VoidCallback? onOpenRemote;

  static const Color _accent = Color(0xFF8E9BFF);
  static const Color _lightAccent = Color(0xFFFFB74D);

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
                    color: _accent.withValues(alpha: on ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.cast_connected_rounded,
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
                            ? '${summary.statusLabel} · 音量 ${summary.volumeLabel}'
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
                if (onOpenRemote != null)
                  IconButton(
                    tooltip: '遥控器',
                    onPressed: onOpenRemote,
                    icon: const Icon(Icons.settings_remote_rounded),
                  ),
                FilledButton.icon(
                  onPressed: isBusy ? null : onPower,
                  icon: Icon(
                    Icons.power_settings_new_rounded,
                    size: 18,
                  ),
                  label: Text(summary.powerLabel),
                ),
              ],
            ),
            if (summary.apps.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              _SectionTitle(title: '应用'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: summary.apps
                    .map((ProjectorApp app) => OutlinedButton(
                          onPressed:
                              on ? () => onOpenApp(app.package) : null,
                          child: Text(app.name),
                        ))
                    .toList(growable: false),
              ),
            ],
            if (summary.inputs.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _SectionTitle(title: '输入源'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: summary.inputs
                    .map((String input) => ChoiceChip(
                          label: Text(input),
                          selected: summary.input == input,
                          showCheckmark: false,
                          onSelected:
                              on ? (bool _) => onInputSelected(input) : null,
                        ))
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 18),
            _SectionTitle(
              title: '音量',
              trailing: summary.volumeLabel,
            ),
            const SizedBox(height: 6),
            GradientSlider(
              value: summary.volume.toDouble(),
              min: summary.volumeMin.toDouble(),
              max: summary.volumeMax.toDouble(),
              colors: const <Color>[
                Color(0xFF42A5F5),
                _accent,
              ],
              enabled: on,
              onChangeEnd: on
                  ? (double value) => onVolumeChanged(value.round())
                  : null,
            ),
            const SizedBox(height: 14),
            _SectionTitle(
              title: '亮度',
              trailing: summary.brightnessLabel,
            ),
            const SizedBox(height: 6),
            GradientSlider(
              value: summary.brightness.toDouble(),
              min: summary.brightnessMin.toDouble(),
              max: summary.brightnessMax.toDouble(),
              colors: const <Color>[
                _lightAccent,
                Color(0xFFFFD180),
              ],
              enabled: on,
              onChangeEnd: on
                  ? (double value) => onBrightnessChanged(value.round())
                  : null,
            ),
            const SizedBox(height: 10),
            _SwitchRow(
              icon: Icons.volume_off_rounded,
              label: '静音',
              value: summary.mute,
              onChanged: on ? (bool _) => onMuteToggle() : null,
            ),
            if (summary.hasPlayback) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _PlaybackButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: '上一首',
                    enabled: on && summary.previousEntityId != null,
                    onTap: () =>
                        _press(summary.previousEntityId),
                  ),
                  _PlaybackButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: '播放',
                    enabled: on && summary.playEntityId != null,
                    onTap: () => _press(summary.playEntityId),
                  ),
                  _PlaybackButton(
                    icon: Icons.pause_rounded,
                    tooltip: '暂停',
                    enabled: on && summary.pauseEntityId != null,
                    onTap: () => _press(summary.pauseEntityId),
                  ),
                  _PlaybackButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一首',
                    enabled: on && summary.nextEntityId != null,
                    onTap: () => _press(summary.nextEntityId),
                  ),
                  _PlaybackButton(
                    icon: Icons.stop_rounded,
                    tooltip: '停止',
                    enabled: on && summary.stopEntityId != null,
                    onTap: () => _press(summary.stopEntityId),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _press(String? entityId) {
    if (entityId != null) onButtonPressed(entityId);
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
              color: ProjectorControlPanel._accent,
            ),
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
          activeThumbColor: ProjectorControlPanel._accent,
        ),
      ],
    );
  }
}

class _PlaybackButton extends StatelessWidget {
  const _PlaybackButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
    );
  }
}

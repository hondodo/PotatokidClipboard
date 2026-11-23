import 'package:flutter/material.dart';

/// 投影仪虚拟遥控：完全对应 MIoT `virtual-remote.press-button` 的按键类型。
///
/// 0 主页 / 1 设置 / 2 返回 / 3 左 / 4 右 / 5 上 / 6 下 / 7 OK /
/// 8 音量- / 9 音量+ / 10 菜单 / 11 静音 / 12 对焦+ / 13 对焦- / 15 电源
class ProjectorRemoteSheet extends StatelessWidget {
  const ProjectorRemoteSheet({
    super.key,
    required this.isOn,
    required this.onKey,
    required this.onPower,
  });

  final bool isOn;
  final ValueChanged<int> onKey;
  final VoidCallback onPower;

  static const int keyHome = 0;
  static const int keySettings = 1;
  static const int keyBack = 2;
  static const int keyLeft = 3;
  static const int keyRight = 4;
  static const int keyUp = 5;
  static const int keyDown = 6;
  static const int keyOk = 7;
  static const int keyVolumeDown = 8;
  static const int keyVolumeUp = 9;
  static const int keyMenu = 10;
  static const int keyMute = 11;
  static const int keyFocusUp = 12;
  static const int keyFocusDown = 13;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 760) {
          return _buildLandscape(context);
        }
        return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '遥控器',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  isOn ? '已开启' : '已关闭',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isOn
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
                IconButton(
                  tooltip: '关闭遥控器',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _RemoteButton(
                  icon: Icons.power_settings_new_rounded,
                  label: isOn ? '关机' : '开机',
                  tooltip: isOn ? '关机' : '开机',
                  enabled: true,
                  onTap: onPower,
                  accent: const Color(0xFFFF8A65),
                ),
                _RemoteButton(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  tooltip: '设置键',
                  enabled: isOn,
                  onTap: () => onKey(keySettings),
                ),
                _RemoteButton(
                  icon: Icons.menu_rounded,
                  label: '菜单',
                  tooltip: '菜单键',
                  enabled: isOn,
                  onTap: () => onKey(keyMenu),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _DirectionPad(
              enabled: isOn,
              onKey: onKey,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _RemoteButton(
                  icon: Icons.home_rounded,
                  label: '主页',
                  tooltip: '主页键',
                  enabled: isOn,
                  onTap: () => onKey(keyHome),
                ),
                _RemoteButton(
                  icon: Icons.undo_rounded,
                  label: '返回',
                  tooltip: '返回键',
                  enabled: isOn,
                  onTap: () => onKey(keyBack),
                ),
                _RemoteButton(
                  icon: Icons.list_rounded,
                  label: '菜单',
                  tooltip: '菜单键',
                  enabled: isOn,
                  onTap: () => onKey(keyMenu),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _RemoteButton(
                  icon: Icons.center_focus_weak_rounded,
                  label: '对焦 -',
                  tooltip: '对焦减',
                  enabled: isOn,
                  small: true,
                  onTap: () => onKey(keyFocusDown),
                ),
                const SizedBox(width: 24),
                _RemoteButton(
                  icon: Icons.center_focus_strong_rounded,
                  label: '对焦 +',
                  tooltip: '对焦加',
                  enabled: isOn,
                  small: true,
                  onTap: () => onKey(keyFocusUp),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _RemoteButton(
                  icon: Icons.volume_down_rounded,
                  label: '音量 -',
                  tooltip: '音量减键',
                  enabled: isOn,
                  onTap: () => onKey(keyVolumeDown),
                ),
                _RemoteButton(
                  icon: Icons.volume_off_rounded,
                  label: '静音',
                  tooltip: '静音键',
                  enabled: isOn,
                  onTap: () => onKey(keyMute),
                ),
                _RemoteButton(
                  icon: Icons.volume_up_rounded,
                  label: '音量 +',
                  tooltip: '音量加键',
                  enabled: isOn,
                  onTap: () => onKey(keyVolumeUp),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '方向键 / OK / 主页 / 返回 / 菜单 / 对焦 / 音量',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildLandscape(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          children: <Widget>[
            _header(context, theme),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 5,
                  child: Column(
                    children: <Widget>[
                      _DirectionPad(enabled: isOn, onKey: onKey),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _RemoteButton(
                            icon: Icons.home_rounded,
                            label: '主页',
                            tooltip: '主页键',
                            enabled: isOn,
                            onTap: () => onKey(keyHome),
                          ),
                          _RemoteButton(
                            icon: Icons.undo_rounded,
                            label: '返回',
                            tooltip: '返回键',
                            enabled: isOn,
                            onTap: () => onKey(keyBack),
                          ),
                          _RemoteButton(
                            icon: Icons.list_rounded,
                            label: '菜单',
                            tooltip: '菜单键',
                            enabled: isOn,
                            onTap: () => onKey(keyMenu),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _RemoteButton(
                            icon: Icons.power_settings_new_rounded,
                            label: isOn ? '关机' : '开机',
                            tooltip: isOn ? '关机' : '开机',
                            enabled: true,
                            onTap: onPower,
                            accent: const Color(0xFFFF8A65),
                          ),
                          _RemoteButton(
                            icon: Icons.settings_rounded,
                            label: '设置',
                            tooltip: '设置键',
                            enabled: isOn,
                            onTap: () => onKey(keySettings),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _RemoteButton(
                            icon: Icons.center_focus_weak_rounded,
                            label: '对焦 -',
                            tooltip: '对焦减',
                            enabled: isOn,
                            small: true,
                            onTap: () => onKey(keyFocusDown),
                          ),
                          _RemoteButton(
                            icon: Icons.center_focus_strong_rounded,
                            label: '对焦 +',
                            tooltip: '对焦加',
                            enabled: isOn,
                            small: true,
                            onTap: () => onKey(keyFocusUp),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _RemoteButton(
                            icon: Icons.volume_down_rounded,
                            label: '音量 -',
                            tooltip: '音量减键',
                            enabled: isOn,
                            onTap: () => onKey(keyVolumeDown),
                          ),
                          _RemoteButton(
                            icon: Icons.volume_off_rounded,
                            label: '静音',
                            tooltip: '静音键',
                            enabled: isOn,
                            onTap: () => onKey(keyMute),
                          ),
                          _RemoteButton(
                            icon: Icons.volume_up_rounded,
                            label: '音量 +',
                            tooltip: '音量加键',
                            enabled: isOn,
                            onTap: () => onKey(keyVolumeUp),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '方向键 / OK / 主页 / 返回 / 菜单 / 对焦 / 音量',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme) {
    return Row(
      children: <Widget>[
        Text(
          '遥控器',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          isOn ? '已开启' : '已关闭',
          style: theme.textTheme.bodySmall?.copyWith(
            color: isOn
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        IconButton(
          tooltip: '关闭遥控器',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({required this.enabled, required this.onKey});

  final bool enabled;
  final ValueChanged<int> onKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _RemoteButton(
            icon: Icons.keyboard_arrow_up_rounded,
            label: '',
            tooltip: '上键',
            enabled: enabled,
            onTap: () => onKey(ProjectorRemoteSheet.keyUp),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RemoteButton(
                icon: Icons.keyboard_arrow_left_rounded,
                label: '',
                tooltip: '左键',
                enabled: enabled,
                onTap: () => onKey(ProjectorRemoteSheet.keyLeft),
              ),
              const SizedBox(width: 14),
              _RemoteButton(
                icon: Icons.radio_button_checked_rounded,
                label: 'OK',
                tooltip: 'OK键',
                enabled: enabled,
                large: true,
                onTap: () => onKey(ProjectorRemoteSheet.keyOk),
              ),
              const SizedBox(width: 14),
              _RemoteButton(
                icon: Icons.keyboard_arrow_right_rounded,
                label: '',
                tooltip: '右键',
                enabled: enabled,
                onTap: () => onKey(ProjectorRemoteSheet.keyRight),
              ),
            ],
          ),
          _RemoteButton(
            icon: Icons.keyboard_arrow_down_rounded,
            label: '',
            tooltip: '下键',
            enabled: enabled,
            onTap: () => onKey(ProjectorRemoteSheet.keyDown),
          ),
        ],
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  const _RemoteButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.accent,
    this.large = false,
    this.small = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final Color? accent;
  final bool large;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double size = large ? 86 : (small ? 48 : 60);
    final Color color = accent ??
        (enabled ? theme.colorScheme.onSurface : theme.colorScheme.outline);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHigh,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: large ? 38 : (small ? 22 : 27),
                  color: enabled ? color : theme.colorScheme.outline,
                ),
              ),
              if (label.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: enabled
                        ? (accent ?? theme.colorScheme.onSurface)
                        : theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

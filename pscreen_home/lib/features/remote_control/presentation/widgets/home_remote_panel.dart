import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/live_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 中控屏遥控面板：5 个场景按钮 + 直播场景下的频道遥控。
///
/// 高亮跟随设备上报的 `scene.kind`；屏保按钮在屏保中变为「退出屏保」。
class HomeRemotePanel extends StatelessWidget {
  const HomeRemotePanel({super.key, required this.panel});

  final RemotePanelContext panel;

  @override
  Widget build(BuildContext context) {
    final String sceneKind = panel.device?.sceneKind ?? '';
    final bool screensaver = sceneKind == 'screensaver';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _SceneButton(
              label: '主页',
              icon: Icons.home_outlined,
              active: sceneKind == 'home',
              onTap: () => panel.onCommand(buildNavCommand('home')),
            ),
            _SceneButton(
              label: '直播',
              icon: Icons.live_tv_outlined,
              active: sceneKind == 'live',
              onTap: () => panel.onCommand(buildNavCommand('live')),
            ),
            _SceneButton(
              label: '天气',
              icon: Icons.wb_sunny_outlined,
              active: sceneKind == 'weather',
              onTap: () => panel.onCommand(buildNavCommand('weather')),
            ),
            _SceneButton(
              label: '设置',
              icon: Icons.settings_outlined,
              active: sceneKind == 'settings',
              onTap: () => panel.onCommand(buildNavCommand('settings')),
            ),
            _SceneButton(
              label: screensaver ? '退出屏保' : '屏保',
              icon: screensaver
                  ? Icons.visibility_outlined
                  : Icons.wallpaper_outlined,
              active: screensaver,
              onTap: () => panel.onCommand(buildNavCommand('screensaver')),
            ),
            if (panel.onSendMessage != null)
              _SceneButton(
                label: '发送消息',
                icon: Icons.send_outlined,
                active: false,
                onTap: panel.onSendMessage!,
              ),
          ],
        ),
        if (sceneKind == 'live') ...<Widget>[
          const Divider(height: 24),
          LiveControlsPanel(
            panel: panel,
            channelsLabel: '频道列表',
            showSendMessage: false,
          ),
        ],
      ],
    );
  }
}

class _SceneButton extends StatelessWidget {
  const _SceneButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        // 当前场景高亮：与页面主题色一致，便于远端一眼定位。
        backgroundColor: active ? scheme.primary : null,
        foregroundColor: active ? scheme.onPrimary : null,
      ),
    );
  }
}

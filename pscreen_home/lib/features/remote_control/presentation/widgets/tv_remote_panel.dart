import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/channel_number_pad.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/home_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/live_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 电视端遥控面板：页面切换行 + 常驻音量行 + 直播控制行。
///
/// 与中控端不同，电视端三个页面（直播/时间/设置）的切换按钮
/// 始终显示，不随当前页面收起；音量行同为常驻，直播控制行也始终可见。
/// 高亮跟随设备上报的 `scene.kind`（`live`/`clock`/`settings`）。
/// 电视端已移除屏保页，故不再提供「屏保」跳转按钮。
class TvRemotePanel extends StatelessWidget {
  const TvRemotePanel({super.key, required this.panel});

  final RemotePanelContext panel;

  @override
  Widget build(BuildContext context) {
    // 离线时不做高亮（上报的场景是旧值）。
    final bool online = panel.online;
    final String sceneKind = online ? (panel.device?.sceneKind ?? '') : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            SceneButton(
              label: '直播',
              icon: Icons.live_tv_outlined,
              active: sceneKind == 'live',
              onTap: online
                  ? () => panel.onCommand(buildNavCommand('live'))
                  : null,
            ),
            // 时间页在电视端是 Tab 1，导航命令沿用共享协议的 `weather` 页名。
            SceneButton(
              label: '时间',
              icon: Icons.schedule_outlined,
              active: sceneKind == 'clock',
              onTap: online
                  ? () => panel.onCommand(buildNavCommand('weather'))
                  : null,
            ),
            SceneButton(
              label: '设置',
              icon: Icons.settings_outlined,
              active: sceneKind == 'settings',
              onTap: online
                  ? () => panel.onCommand(buildNavCommand('settings'))
                  : null,
            ),
            if (panel.onSendMessage != null)
              SceneButton(
                label: '发送消息',
                icon: Icons.send_outlined,
                active: false,
                onTap: online ? panel.onSendMessage : null,
              ),
          ],
        ),
        const Divider(height: 24),
        // 音量行：系统级、常驻（无论是否在直播都显示）。
        VolumeControlsPanel(panel: panel),
        const Divider(height: 24),
        LiveControlsPanel(
          panel: panel,
          channelsLabel: '频道列表',
          showSendMessage: false,
          showSleepTimer: true,
        ),
        const Divider(height: 24),
        // 数字键直选频道：逐位直发电视端，本地只回显、结算收口电视端。
        // 面板挂在可滚动父级里（ParentalRemotePage 的 body 可滚），不会溢出。
        ChannelNumberPad(
          enabled: online,
          onCommand: panel.onCommand,
          onHint: panel.onHint,
        ),
      ],
    );
  }
}

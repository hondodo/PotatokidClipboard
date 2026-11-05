import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/home_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/live_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';

/// 家长端（`kind == 'parent'`）遥控面板。
///
/// 家长端没有中控桌面场景（主页/直播/天气/屏保）与中控专属设置，
/// 因此只保留系统级音量行与「发送消息」入口；不渲染页面切换按钮，
/// 避免把 parent 设备当成中控屏或电视端。
class ParentRemotePanel extends StatelessWidget {
  const ParentRemotePanel({super.key, required this.panel});

  final RemotePanelContext panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (panel.onSendMessage != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SceneButton(
                label: '发送消息',
                icon: Icons.send_outlined,
                active: false,
                onTap: panel.online ? panel.onSendMessage : null,
              ),
            ],
          ),
        const Divider(height: 24),
        VolumeControlsPanel(panel: panel),
      ],
    );
  }
}

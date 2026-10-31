import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/online_dot.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/playback_badge.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 一台被控设备的遥控面板容器。
///
/// 进入时 `watch`、离开时 `unwatch`：服务端随后会把该设备的场景与频道列表
/// 推给本控制端，面板据此切换类型与高亮。设备离线时保留按钮
/// （消息由服务端离线队列缓存）。
class TargetRemotePanel extends StatefulWidget {
  const TargetRemotePanel({
    super.key,
    required this.account,
    required this.onCommand,
    this.onSendMessage,
    this.onHint,
    this.title,
    this.showHeader = true,
  });

  final String account;
  final ValueChanged<String> onCommand;

  /// 面板内「发送消息」按钮的回调；为空时不显示该按钮。
  final VoidCallback? onSendMessage;

  /// 轻提示（如「已发送」），由宿主页展示成不遮挡的小胶囊。
  final void Function(String message, {bool error})? onHint;

  /// 显示名（默认用账号）。
  final String? title;

  /// 是否显示设备名/在线/场景一行。
  final bool showHeader;

  @override
  State<TargetRemotePanel> createState() => _TargetRemotePanelState();
}

class _TargetRemotePanelState extends State<TargetRemotePanel> {
  StreamSubscription<RealtimeDeviceState>? _sub;

  RealtimeChannel get _channel => Injection.get<RealtimeChannel>();

  String get _account => widget.account.trim();

  @override
  void initState() {
    super.initState();
    _attach(_account);
  }

  @override
  void didUpdateWidget(covariant TargetRemotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.trim() != _account) {
      _detach(oldWidget.account.trim());
      _attach(_account);
    }
  }

  @override
  void dispose() {
    _detach(_account);
    super.dispose();
  }

  void _attach(String account) {
    if (account.isEmpty) return;
    _channel.watch(account);
    _sub = _channel.deviceStates.where((RealtimeDeviceState state) => state.account == account).listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _detach(String account) {
    _sub?.cancel();
    _sub = null;
    if (account.isNotEmpty) _channel.unwatch(account);
  }

  @override
  Widget build(BuildContext context) {
    final RealtimeDeviceState? info = _channel.deviceInfoOf(_account);
    final bool online = _channel.isOnline(_account);
    final RemotePanelContext panel = RemotePanelContext(
      account: _account,
      device: info,
      online: online,
      onCommand: widget.onCommand,
      onSendMessage: widget.onSendMessage,
      onHint: widget.onHint,
    );
    // 离线时场景与播放状态都是上一次上报的旧值，继续展示会误导
    // （例如设备已关机却仍写「正在播放」），这里只显示「离线」。
    final String sceneTitle = online ? '${info?.scene['title'] ?? ''}' : '';
    final String kind = info?.kind ?? '';
    // 播放状态只有直播场景才有意义（其它页面播放器已销毁）。
    final String playbackLabel = (online && info?.sceneKind == 'live') ? (info?.playbackLabel ?? '') : '';
    final bool enabled = panel.online;
    // 当前设备音量（0-100，被控端随 state 帧上报）。
    final int? volume = enabled ? panel.device?.sceneVolume : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showHeader)
          Row(
            children: <Widget>[
              OnlineDot(online: online),
              if (volume != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.volume_up_rounded, size: 18),
                    const SizedBox(width: 4),
                    Text('$volume'),
                  ],
                ),
              ],
              const SizedBox(width: 8),
              // Text(widget.title ?? widget.account, style: const TextStyle(fontWeight: FontWeight.w600)),
              // const SizedBox(width: 8),
              Text(switch (kind) {
                'home' => '中控屏',
                'tv' => '电视',
                _ => '未知设备',
              }, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (sceneTitle.isNotEmpty) ...<Widget>[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    sceneTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
              if (!online) ...<Widget>[
                const SizedBox(width: 12),
                Text('离线', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              if (playbackLabel.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                PlaybackBadge(label: playbackLabel, state: info?.playbackState ?? ''),
              ],
            ],
          ),
        if (widget.showHeader) const SizedBox(height: 8),
        if (!online)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('设备离线，暂不能发送指令', style: TextStyle(fontSize: 12)),
          )
        else if (info == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('等待设备上报状态…', style: TextStyle(fontSize: 12)),
          )
        else if (kind.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('未识别设备类型，使用通用面板', style: TextStyle(fontSize: 12)),
          ),
        RemotePanelRegistry.build(panel),
      ],
    );
  }
}

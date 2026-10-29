import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
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
    _sub = _channel.deviceStates
        .where((RealtimeDeviceState state) => state.account == account)
        .listen((_) {
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
    final String playbackLabel =
        (online && info?.sceneKind == 'live') ? (info?.playbackLabel ?? '') : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showHeader)
          Row(
            children: <Widget>[
              _OnlineDot(online: online),
              const SizedBox(width: 8),
              Text(
                widget.title ?? widget.account,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                switch (kind) {
                  'home' => '中控屏',
                  'tv' => '电视',
                  _ => '未知设备',
                },
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (sceneTitle.isNotEmpty) ...<Widget>[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    sceneTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
              if (!online) ...<Widget>[
                const SizedBox(width: 12),
                Text(
                  '离线',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (playbackLabel.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                _PlaybackBadge(
                  label: playbackLabel,
                  state: info?.playbackState ?? '',
                ),
              ],
            ],
          ),
        if (widget.showHeader) const SizedBox(height: 8),
        if (!online)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '设备离线，暂不能发送指令',
              style: TextStyle(fontSize: 12),
            ),
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

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? const Color(0xFF34C759) : const Color(0xFFBDBDBD),
      ),
    );
  }
}

/// 播放状态徽标：正常绿 / 起播蓝 / 重试橙 / 失败红。
class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({required this.label, required this.state});

  final String label;
  final String state;

  Color get _color => switch (state) {
        'play_ok' => const Color(0xFF34C759),
        'play_start' => const Color(0xFF4F8CFF),
        'play_retry' => const Color(0xFFFFB020),
        'play_fail' => const Color(0xFFFF5A5F),
        _ => const Color(0xFF9AA4B2),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: _color, height: 1.4),
      ),
    );
  }
}

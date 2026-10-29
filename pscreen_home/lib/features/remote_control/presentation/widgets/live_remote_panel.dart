import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/data/favorite_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 直播遥控的通用操作行：音量± / 静音 / 频道列表 / 发送消息。
///
/// 电视端（`tv`）与中控屏直播场景（`home`）共用，保证两端遥控内容一致；
/// 频道列表点按钮后打开底部弹窗（搜索 + 收藏 + 全量名单），不在原地展开。
class LiveControlsPanel extends StatelessWidget {
  const LiveControlsPanel({
    super.key,
    required this.panel,
    required this.channelsLabel,
  });

  final RemotePanelContext panel;

  /// 频道按钮的文案（电视端「选择频道」／中控端「频道列表」）。
  final String channelsLabel;

  @override
  Widget build(BuildContext context) {
    final int count = panel.device?.channels.length ?? 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _CmdButton(
          label: '音量+',
          onTap: () => panel.onCommand(buildCommandEnvelope('volume_up')),
        ),
        _CmdButton(
          label: '音量-',
          onTap: () => panel.onCommand(buildCommandEnvelope('volume_down')),
        ),
        _CmdButton(
          label: '静音',
          onTap: () => panel.onCommand(buildCommandEnvelope('mute')),
        ),
        OutlinedButton.icon(
          onPressed: () => _openChannels(context),
          icon: const Icon(Icons.list, size: 20),
          label: Text(count > 0 ? '$channelsLabel（$count）' : channelsLabel),
        ),
        if (panel.onSendMessage != null)
          FilledButton.tonalIcon(
            onPressed: panel.onSendMessage,
            icon: const Icon(Icons.send_outlined, size: 20),
            label: const Text('发送消息'),
          ),
      ],
    );
  }

  void _openChannels(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) =>
          _ChannelSheet(panel: panel, title: channelsLabel),
    );
  }
}

class _CmdButton extends StatelessWidget {
  const _CmdButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}

/// 频道选择弹窗：跟随设备状态刷新（当前频道高亮），选中后发送命令并关闭。
class _ChannelSheet extends StatefulWidget {
  const _ChannelSheet({required this.panel, required this.title});

  final RemotePanelContext panel;
  final String title;

  @override
  State<_ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends State<_ChannelSheet> {
  StreamSubscription<RealtimeDeviceState>? _sub;

  RealtimeChannel get _channel => Injection.get<RealtimeChannel>();

  @override
  void initState() {
    super.initState();
    _sub = _channel.deviceStates
        .where((RealtimeDeviceState state) => state.account == widget.panel.account)
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RealtimeDeviceState? device = _channel.deviceInfoOf(widget.panel.account);
    final int count = device?.channels.length ?? 0;
    final RemotePanelContext panel = RemotePanelContext(
      account: widget.panel.account,
      device: device,
      online: widget.panel.online,
      // 选中频道后发送并关闭弹窗。
      onCommand: (String command) {
        widget.panel.onCommand(command);
        Navigator.of(context).maybePop();
      },
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: <Widget>[
                Text(
                  count > 0 ? '${widget.title}（$count）' : widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: LiveRemotePanel(panel: panel),
          ),
        ],
      ),
    );
  }
}

/// 直播遥控：搜索 + 收藏置顶 + 全量频道列表。
///
/// 频道名单来自设备上报的 `state.channels`（启动时一次性下发，列表变化才刷新），
/// 点击只发送「频道名 + 序号」，避免近千条名单反复传输。
class LiveRemotePanel extends StatefulWidget {
  const LiveRemotePanel({super.key, required this.panel});

  final RemotePanelContext panel;

  @override
  State<LiveRemotePanel> createState() => _LiveRemotePanelState();
}

class _LiveRemotePanelState extends State<LiveRemotePanel> {
  static const Duration searchDebounce = Duration(milliseconds: 300);

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Set<String> _favorites = <String>{};

  String get _account => widget.panel.account;

  @override
  void initState() {
    super.initState();
    _favorites = FavoriteStore.instance.channelsOf(_account);
  }

  @override
  void didUpdateWidget(covariant LiveRemotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同一面板切换被控设备时重新读取收藏。
    if (oldWidget.panel.account != _account) {
      _favorites = FavoriteStore.instance.channelsOf(_account);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Future<void> _toggleFavorite(String name) async {
    await FavoriteStore.instance.toggle(_account, name);
    if (!mounted) return;
    setState(() => _favorites = FavoriteStore.instance.channelsOf(_account));
  }

  @override
  Widget build(BuildContext context) {
    final List<String> names =
        widget.panel.device?.channels ?? const <String>[];
    if (names.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('等待设备上报频道列表…'),
      );
    }

    final String query = _query.toLowerCase();
    final List<int> matches = <int>[];
    for (int i = 0; i < names.length; i++) {
      if (query.isEmpty || names[i].toLowerCase().contains(query)) {
        matches.add(i);
      }
    }
    // 收藏置顶：先收藏（保持原序号顺序），再其余。
    final List<int> favorites = <int>[
      for (final int i in matches)
        if (_favorites.contains(names[i])) i,
    ];
    final List<int> others = <int>[
      for (final int i in matches)
        if (!_favorites.contains(names[i])) i,
    ];
    final List<int> ordered = <int>[...favorites, ...others];
    final String current = widget.panel.device?.channelName ?? '';
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _search,
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: '搜索频道（${names.length} 个，长按收藏）',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: ordered.isEmpty
              ? const Center(child: Text('没有匹配的频道'))
              : ListView.builder(
                  itemCount: ordered.length,
                  itemBuilder: (BuildContext context, int i) {
                    final int index = ordered[i];
                    final String name = names[index];
                    final bool favorite = _favorites.contains(name);
                    final bool active = name == current;
                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(
                        favorite ? Icons.star : Icons.star_border,
                        size: 20,
                        color: favorite ? Colors.amber : null,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: active
                            ? TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                      trailing: active
                          ? Text(
                              '正在播放',
                              style: TextStyle(color: scheme.primary),
                            )
                          : Text('${index + 1}'),
                      onTap: () => widget.panel.onCommand(
                        buildChannelCommand(name: name, index: index),
                      ),
                      onLongPress: () => _toggleFavorite(name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

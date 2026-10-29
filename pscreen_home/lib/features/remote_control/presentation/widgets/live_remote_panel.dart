import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/data/favorite_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

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
        child: Text('等待电视上报频道列表…'),
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

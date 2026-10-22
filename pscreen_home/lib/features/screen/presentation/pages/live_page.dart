import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_player_view.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 直播页：播放器铺满整个 body，频道列表是 [Stack] 上层的右侧浮层。
///
/// 交互：
/// - 进入页面 → 右侧列表自动显示，并开始 [LivePage._hideDelay] 倒计时；
/// - 倒计时内无操作 → 列表自动隐藏；
/// - 显示期间任何操作（点频道 / 点上一台 / 点下一台）→ 重新计时；
/// - 点「列表与底部按钮之外」的播放器空白处 → 显示 ⇄ 隐藏 切换；
/// - 底部「上一台 / 下一台」按钮居中，与列表同层，一起跟随显隐，
///   列表停靠右边不会遮住它们。
class LivePage extends StatefulWidget {
  const LivePage({super.key, this.enablePlayer = true});

  /// 是否实例化真实播放器（测试环境置 false）。
  final bool enablePlayer;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  /// 无操作多久后自动隐藏浮层。
  static const Duration _hideDelay = Duration(seconds: 10);

  /// 右侧频道列表浮层宽度。
  static const double _listWidth = 320;

  /// 浮层（右侧列表 + 底部切台按钮）是否显示。
  bool _overlayVisible = true;

  /// 自动隐藏计时器。
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // 进入页面：浮层自动显示并开始倒计时。
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 重新开始「无操作 N 秒后隐藏」的倒计时。
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted) return;
      setState(() => _overlayVisible = false);
    });
  }

  /// 点播放器空白处（列表与底部按钮之外）：显示 ⇄ 隐藏 切换。
  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
          ),
        ],
      ),
      body: BlocConsumer<IptvBloc, IptvState>(
        listener: (BuildContext context, IptvState state) {
          // 共享包的频道控制器按「频道总数」判断 select/next 是否有效，
          // 这里同步一次，触屏点选才能立即切台。
          // 放在 listener（状态变化时）而不是 build：build 阶段的副作用会
          // 在重建中触发 notifyListeners，导致不必要的重绘。
          LiveChannelController.instance.setCount(state.channels.length);
        },
        builder: (BuildContext context, IptvState state) {
          if (state.isLoading && state.channels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && state.channels.isEmpty) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final List<IptvChannel> channels = state.channels;
          // 点「列表与底部按钮之外」的播放器空白区，切换浮层显隐。
          // 列表面板 / 切台按钮自带点击处理，会吃掉各自区域的点按，
          // 不会冒泡到这里触发切换。
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleOverlay,
            child: Stack(
              children: <Widget>[
                // 播放器铺满整个区域。
                Positioned.fill(
                  child: widget.enablePlayer && channels.isNotEmpty
                      ? LivePlayerView(channels: channels)
                      : const ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Text(
                              '播放器',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ),
                        ),
                ),
                // 左下角当前频道名（始终显示，便于关掉浮层后仍知道在看什么）。
                if (channels.isNotEmpty)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _ChannelNameBadge(channels: channels),
                  ),
                // 底部居中「上一台 / 下一台」，与列表同层，跟随显隐。
                if (_overlayVisible && channels.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: _ChannelSwitchControls(onInteract: _scheduleHide),
                    ),
                  ),
                // 右侧频道列表浮层，跟随显隐。
                if (_overlayVisible && channels.isNotEmpty)
                  Positioned(
                    top: 12,
                    bottom: 12,
                    right: 12,
                    width: _listWidth,
                    child: _ChannelListPanel(
                      channels: channels,
                      onSelect: _scheduleHide,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 左下角当前频道名（始终显示）。
class _ChannelNameBadge extends StatelessWidget {
  const _ChannelNameBadge({required this.channels});

  final List<IptvChannel> channels;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LiveChannelController.instance,
      builder: (BuildContext context, Widget? child) {
        final int index = LiveChannelController.instance.index;
        if (index < 0 || index >= channels.length) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            channels[index].name,
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        );
      },
    );
  }
}

/// 底部居中「上一台 / 下一台」：点击除了切台，还重置自动隐藏计时。
class _ChannelSwitchControls extends StatelessWidget {
  const _ChannelSwitchControls({required this.onInteract});

  /// 有操作时回调（用于重置自动隐藏计时）。
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: '上一台',
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: () {
              LiveChannelController.instance.previous();
              onInteract();
            },
          ),
          IconButton(
            tooltip: '下一台',
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: () {
              LiveChannelController.instance.next();
              onInteract();
            },
          ),
        ],
      ),
    );
  }
}

/// 右侧频道列表浮层：点选切台，点选后保持显示并重置计时。
class _ChannelListPanel extends StatelessWidget {
  const _ChannelListPanel({required this.channels, required this.onSelect});

  final List<IptvChannel> channels;

  /// 点选频道后的回调（用于重置自动隐藏计时）。
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: LiveChannelController.instance,
        builder: (BuildContext context, Widget? child) {
          final int current = LiveChannelController.instance.index;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: channels.length,
            itemBuilder: (BuildContext context, int index) {
              final IptvChannel channel = channels[index];
              return ListTile(
                dense: true,
                title: Text(
                  channel.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: channel.group == null || channel.group!.isEmpty
                    ? null
                    : Text(
                        channel.group!,
                        style: const TextStyle(color: Colors.white54),
                      ),
                selected: index == current,
                selectedTileColor: Colors.white24,
                onTap: () {
                  LiveChannelController.instance.select(index);
                  onSelect();
                },
              );
            },
          );
        },
      ),
    );
  }
}

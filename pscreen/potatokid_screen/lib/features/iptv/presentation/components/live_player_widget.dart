import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/channel_bar.dart';

/// 全屏直播播放组件：持有 [Player]/[VideoController]，进入自动播放首个频道。
///
/// 频道切换由全局 [LiveChannelController] 驱动（壳层「上/下」键），
/// 频道条浮在右侧，显隐跟随 [AppState.showChannels]。
class LivePlayerWidget extends StatefulWidget {
  const LivePlayerWidget({super.key, required this.channels});

  /// 已解析的频道列表（非空）
  final List<IptvChannel> channels;

  @override
  State<LivePlayerWidget> createState() => _LivePlayerWidgetState();
}

class _LivePlayerWidgetState extends State<LivePlayerWidget> {
  Player? _player;
  VideoController? _controller;
  final LiveChannelController _channelController =
      LiveChannelController.instance;
  Timer? _toastTimer;
  String? _toastName; // 左下角当前频道名提示（5 秒后消失）
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // MediaKit.ensureInitialized() 已在 main() 中调用。
    final Player player = Player();
    _player = player;
    _controller = VideoController(player);
    // 同步频道数与当前选中频道，随后监听上/下键的切换。
    _syncChannels();
    _channelController.addListener(_onChannelChanged);
    _openChannel(_channelController.index, force: true);
  }

  @override
  void didUpdateWidget(covariant LivePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels.length != widget.channels.length) {
      _syncChannels();
      _openChannel(_channelController.index, force: true);
    }
  }

  void _syncChannels() {
    _channelController.setCount(widget.channels.length);
  }

  void _onChannelChanged() {
    _openChannel(_channelController.index);
  }

  Future<void> _openChannel(int index, {bool force = false}) async {
    if (index < 0 || index >= widget.channels.length) return;
    final bool changed = index != _currentIndex;
    if (!force && !changed) return;
    _currentIndex = index;
    if (mounted) setState(() {});
    if (changed || force) {
      await _player?.open(Media(widget.channels[index].url));
      _showChannelToast(widget.channels[index].name);
    }
  }

  /// 左下角显示当前频道名，5 秒后自动消失。
  void _showChannelToast(String name) {
    _toastTimer?.cancel();
    setState(() => _toastName = name);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toastName = null);
    });
  }

  @override
  void dispose() {
    _channelController.removeListener(_onChannelChanged);
    _toastTimer?.cancel();
    _player?.dispose();
    _player = null;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoController? controller = _controller;
    if (controller == null || widget.channels.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 视频始终全屏铺满。
        ColoredBox(
          color: Colors.black,
          child: Video(
            controller: controller,
            controls: NoVideoControls,
          ),
        ),
        // 右侧频道条：显隐由 showChannels 开关控制（OK 同步 / 菜单键单独呼出）。
        Align(
          alignment: Alignment.centerRight,
          child: BlocBuilder<AppBloc, AppState>(
            buildWhen: (previous, current) =>
                previous.showChannels != current.showChannels,
            builder: (context, state) {
              return AnimatedSlide(
                offset: state.showChannels
                    ? Offset.zero
                    : const Offset(1, 0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: ChannelBar(
                  channels: widget.channels,
                  selectedIndex: _channelController.index,
                  onChanged: _channelController.select,
                ),
              );
            },
          ),
        ),
// 左下角频道名提示（5 秒后自动消失）。
        if (_toastName != null)
          Positioned(
            left: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _toastName!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }
}
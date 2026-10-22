import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 触屏版直播播放器。
///
/// 与电视端 `LivePlayerWidget` 的差异：不做遥控焦点 / 频道条 / 看门狗 /
/// 代理池等 TV 专属逻辑，只保留「打开当前频道 + 上下台 + 播放暂停」。
/// 频道切换统一走共享包的 [LiveChannelController]（触屏点选走 `select`，
/// 立即提交播放，不延迟）。
class LivePlayerView extends StatefulWidget {
  const LivePlayerView({super.key, required this.channels});

  /// 已解析的频道列表（非空）。
  final List<IptvChannel> channels;

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView> {
  late final Player _player;
  late final VideoController _videoController;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    ChannelInfoProvider.instance.setChannels(widget.channels);
    LiveChannelController.instance.setCount(widget.channels.length);
    LiveChannelController.instance.onPlayCommit.addListener(_openCurrent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrent());
  }

  @override
  void didUpdateWidget(covariant LivePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels.length != widget.channels.length) {
      ChannelInfoProvider.instance.setChannels(widget.channels);
      LiveChannelController.instance.setCount(widget.channels.length);
    }
  }

  @override
  void dispose() {
    LiveChannelController.instance.onPlayCommit.removeListener(_openCurrent);
    _player.dispose();
    super.dispose();
  }

  void _openCurrent() {
    if (!mounted) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    final String url = widget.channels[index].primaryUrl;
    if (url.isEmpty) return;
    _player.open(Media(url));
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _player.play();
    } else {
      _player.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int index = LiveChannelController.instance.index;
    final String name = index >= 0 && index < widget.channels.length
        ? widget.channels[index].name
        : '';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(controller: _videoController, controls: NoVideoControls),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '上一台',
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () => LiveChannelController.instance.previous(),
                ),
                IconButton(
                  tooltip: _playing ? '暂停' : '播放',
                  iconSize: 36,
                  color: Colors.white,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: _togglePlay,
                ),
                IconButton(
                  tooltip: '下一台',
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => LiveChannelController.instance.next(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

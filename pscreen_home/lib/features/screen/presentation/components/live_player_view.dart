import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 触屏版直播播放器：只负责「打开当前频道 + 视频铺满」。
///
/// 与电视端 `LivePlayerWidget` 的差异：不做遥控焦点 / 频道条 / 看门狗 /
/// 代理池等 TV 专属逻辑。频道切换统一走共享包的 [LiveChannelController]
/// （触屏点选走 `select`，立即提交播放，不延迟）。
///
/// 播放器**铺满父级**（由外层 [Stack] 的 `Positioned.fill` 约束），视频用
/// [BoxFit.contain] 自适应留边；频道名 / 切台按钮 / 频道列表等浮层一律由外层
/// 页面的 [Stack] 负责，本控件不内置任何 controls。
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

  @override
  Widget build(BuildContext context) {
    // 黑底铺满父级，视频按 contain 自适应（不同画幅的流都完整显示、留边）。
    return ColoredBox(
      color: Colors.black,
      child: Video(
        controller: _videoController,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      ),
    );
  }
}

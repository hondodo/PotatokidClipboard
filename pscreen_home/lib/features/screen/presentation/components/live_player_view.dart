import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';

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

  /// 最近一次 open 的时间（播放事件上报的耗时基准）。
  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    ChannelInfoProvider.instance.setChannels(widget.channels);
    LiveChannelController.instance.setCount(widget.channels.length);
    LiveChannelController.instance.onPlayCommit.addListener(_openCurrent);
    // ---- 播放状态上报（纯观测：只订阅状态，不改变任何播放行为）----
    // 进入播放 = 成功（去重由上报服务负责，连发只报第一条）。
    _playingSub = _player.stream.playing.listen((bool value) {
      if (value) _report('play_ok');
    });
    // 播放失败：本页无重试逻辑，终态即失败（忽略与电视端同组的非致命 seek 报错）。
    _errorSub = _player.stream.error.listen((String msg) {
      final String trimmed = msg.trim();
      if (trimmed.contains('Cannot seek in this stream') || trimmed.contains('--force-seekable')) {
        return;
      }
      _report('play_fail', reason: trimmed);
    });
    // 直播流被对端断开且无 error 时会走到 completed，同样记为失败。
    _completedSub = _player.stream.completed.listen((bool done) {
      if (done) _report('play_fail', reason: 'completed=true');
    });
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
    _playingSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// 播放状态上报（**纯观测**：只读当前索引/耗时，不参与播放决策；
  /// DI 未就绪等异常一律吞掉，绝不影响播放）。防刷屏由上报服务内部完成。
  void _report(String state, {int? index, String reason = ''}) {
    try {
      final int i = index ?? LiveChannelController.instance.index;
      if (i < 0 || i >= widget.channels.length) return;
      final IptvChannel channel = widget.channels[i];
      Injection.get<ReportingService>().notifyPlayback(
        state,
        channel: channel.name,
        // 本页固定播 primaryUrl（即第一源），且不做多源回退。
        sourceIndex: 1,
        sourceTotal: channel.sources.length,
        sourceUrl: channel.primaryUrl,
        reason: reason,
        round: 0,
        elapsed: DateTime.now().difference(_lastOpenAt),
      );
    } catch (_) {
      // 上报不可用不影响播放。
    }
  }

  void _openCurrent() {
    if (!mounted) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    final String url = widget.channels[index].primaryUrl;
    if (url.isEmpty) return;
    _lastOpenAt = DateTime.now();
    _player.open(Media(url));
    _report('play_start', index: index);
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

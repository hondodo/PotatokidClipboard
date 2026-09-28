import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/application/channel_source_cache.dart';
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

  /// 当前频道正使用的源序号（同频道多源，失败时递增回退）。
  int _currentSource = 0;
  bool _handleFailureBusy = false;
  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  /// 打开某源后若迟迟未进入播放的超时看门狗（解决“连了很久没反应”）。
  Timer? _hangWatchdog;
  static const Duration _hangTimeout = Duration(seconds: 60);

  /// 进入播放即取消看门狗。
  StreamSubscription<bool>? _playingSub;

  /// 最近一次记住的「频道|源URL」，避免重复写盘。
  String? _lastRemembered;

  /// 频道列表「30 秒无操作」自动收起的计时器。
  Timer? _channelsHideTimer;
  static const Duration _channelsHideDelay = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    // MediaKit.ensureInitialized() 已在 main() 中调用。
    final Player player = Player();
    _player = player;
    _controller = VideoController(player);
    // 源播放失败/结束（completed=true）时尝试回退到下一个源。
    _errorSub = player.stream.error.listen((_) => _onPlaybackIssue());
    _completedSub = player.stream.completed.listen((done) {
      if (done) _onPlaybackIssue();
    });
    // 进入播放即取消看门狗，并记住当前频道可用的源。
    _playingSub = player.stream.playing.listen((value) {
      if (value) {
        _hangWatchdog?.cancel();
        _rememberCurrentSource();
      }
    });
    // 同步频道数与当前选中频道，随后监听上/下键的切换。
    _syncChannels();
    _channelController.addListener(_onChannelChanged);
    _restoreLastChannel();
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
    // 换台算一次列表操作：显示列表并重置 30 秒计时。
    _markChannelsActivity();
    // 记录当前频道，下次启动据此恢复。
    _rememberCurrentChannel();
  }

  /// 启动时恢复上次播放的频道（仍存在则切过去，否则默认首台）。
  Future<void> _restoreLastChannel() async {
    // 默认首台(0)。
    int target = _channelController.index;
    final String? last = await ChannelSourceCache.instance.lastChannelName();
    if (last != null) {
      final int idx =
          widget.channels.indexWhere((IptvChannel c) => c.name == last);
      if (idx >= 0 && idx < widget.channels.length) target = idx;
    }
    // 目标即当前索引（如首台）时 select 不会触发 listener，需手动打开。
    if (target != _channelController.index) {
      _channelController.select(target); // 触发 _onChannelChanged → 打开并记录
    } else {
      await _openChannel(target, force: true);
    }
  }

  /// 记录当前频道名。
  void _rememberCurrentChannel() {
    final IptvChannel? channel = _currentChannel();
    if (channel == null) return;
    ChannelSourceCache.instance.rememberChannel(channel.name);
  }

  /// 频道列表操作（换台/滑动）：显示列表并重置 30 秒自动收起计时。
  void _markChannelsActivity() {
    if (!mounted) return;
    context.read<AppBloc>().add(const SetChannels(true));
    _armChannelsHide();
  }

  void _armChannelsHide() {
    _channelsHideTimer?.cancel();
    _channelsHideTimer = Timer(_channelsHideDelay, () {
      _channelsHideTimer = null;
      if (!mounted) return;
      context.read<AppBloc>().add(const SetChannels(false));
    });
  }

  Future<void> _openChannel(int index, {bool force = false}) async {
    if (index < 0 || index >= widget.channels.length) return;
    final bool changed = index != _currentIndex;
    if (!force && !changed) return;
    _currentIndex = index;
    _currentSource = 0;
    // 优先从上次可用源起播（记忆的 URL 已不在此频道则回落首源）。
    final String? preferred =
        await ChannelSourceCache.instance.preferredSourceOf(
      widget.channels[index].name,
    );
    if (preferred != null) {
      final int idx = widget.channels[index].sources.indexOf(preferred);
      if (idx >= 0) _currentSource = idx;
    }
    if (mounted) setState(() {});
    if (changed || force) {
      // 切台时抑制旧流的 error/completing 干扰。
      _handleFailureBusy = true;
      await _playCurrentSource();
      _handleFailureBusy = false;
      _showChannelToast(_channelSourceLabel());
    }
  }

  /// 当前源播放成功后，记住这个频道可用源的 URL。
  void _rememberCurrentSource() {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    final String url = channel.sources[idx];
    if (url.isEmpty) return;
    final String marker = '${channel.name}|$url';
    if (marker == _lastRemembered) return; // 未变化则跳过写盘
    _lastRemembered = marker;
    // 异步记盘，不阻塞播放。
    ChannelSourceCache.instance.rememberSource(channel.name, url);
  }

  IptvChannel? _currentChannel() {
    if (_currentIndex < 0 || _currentIndex >= widget.channels.length) {
      return null;
    }
    return widget.channels[_currentIndex];
  }

  /// 打开当前频道的当前源。
  Future<void> _playCurrentSource() async {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _lastOpenAt = DateTime.now();
    _startHangWatchdog();
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 播放频道${channel.name}源(${idx + 1}/${channel.sources.length})',
    );
    await _player?.open(Media(channel.sources[idx]));
  }

  /// 左下角频道名提示文案：`频道名称 (源 i/N)`。
  String _channelSourceLabel() {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return '';
    final int i = (_currentSource + 1).clamp(1, channel.sources.length);
    return '${channel.name} (源 $i/${channel.sources.length})';
  }

  /// 启动“打开后长时间未播放”超时看门狗；进入播放后由 playing 订阅取消。
  void _startHangWatchdog() {
    _hangWatchdog?.cancel();
    _hangWatchdog = Timer(_hangTimeout, () {
      if (!mounted) return;
      // 已在使用其它源/已开始播放则忽略。
      if (_player?.state.playing ?? false) return;
      _onPlaybackIssue(); // 卡住：循环回退下一个源
    });
  }

  /// 播放失败/结束：循环回退到下一个源。
  ///
  /// 多源时按 1-2-3-4-1-2-… 循环；单源时反复重试同一源 1-1-1-…。
  /// 用 busy 标志与 700ms 冷却抑制旧源残留事件与过热循环。
  Future<void> _onPlaybackIssue() async {
    if (_handleFailureBusy || !mounted) return;
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    // 刚 open 后立刻来的事件多为旧源残留，忽略，避免误回退。
    if (DateTime.now().difference(_lastOpenAt).inMilliseconds < 700) return;
    _handleFailureBusy = true;
    _currentSource = (_currentSource + 1) % channel.sources.length;
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 切换频道${channel.name}源(${_currentSource + 1}/${channel.sources.length})',
    );
    await _playCurrentSource();
    _handleFailureBusy = false;
    // 刷新左下角里的源序号提示。
    if (mounted) _showChannelToast(_channelSourceLabel());
  }

  /// 左下角显示当前频道名与源序号，5 秒后自动消失。
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
    _channelsHideTimer?.cancel();
    _hangWatchdog?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
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
          child: Video(controller: controller, controls: NoVideoControls),
        ),
        // 右侧频道条：显隐由 showChannels 开关控制（OK 同步 / 菜单键单独呼出）。
        Align(
          alignment: Alignment.centerRight,
          child: BlocBuilder<AppBloc, AppState>(
            buildWhen: (previous, current) =>
                previous.showChannels != current.showChannels,
            builder: (context, state) {
              // 列表处于可见时确保有 30 秒计时（初始显示也算）。
              if (state.showChannels &&
                  (mounted && _channelsHideTimer == null)) {
                _armChannelsHide();
              }
              return AnimatedSlide(
                offset: state.showChannels ? Offset.zero : const Offset(1, 0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                // 滑动列表也算操作：重置 30 秒计时并确保显示。
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    if (state.showChannels) _markChannelsActivity();
                    return false;
                  },
                  child: ChannelBar(
                    channels: widget.channels,
                    selectedIndex: _channelController.index,
                    onChanged: _channelController.select,
                    visible: state.showChannels,
                  ),
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

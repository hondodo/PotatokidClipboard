import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';
import 'package:potatokid_screen/features/iptv/application/channel_source_cache.dart';
import 'package:potatokid_screen/features/iptv/application/home_now_playing_controller.dart';
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

class _LivePlayerWidgetState extends State<LivePlayerWidget> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _controller;
  final LiveChannelController _channelController = LiveChannelController.instance;
  Timer? _toastTimer;

  /// 左下角频道名提示（ValueNotifier 避免 setState 导致整棵树重建而闪烁）
  final ValueNotifier<String?> _toastNameVN = ValueNotifier<String?>(null);
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
  StreamSubscription<int?>? _widthSub;

  /// 黑屏判定：是否出现过真实视频帧（width>0）。
  bool _playedVideo = false;

  /// 「持续缓冲卡死」检测：playing 且 buffering 连续累计超阈值才回退。
  Timer? _bufferStallWatch;
  Duration _bufferingAccum = Duration.zero;
  static const Duration _bufferStallThreshold = Duration(seconds: 30);

  /// 最近一次记住的「频道|源URL」，避免重复写盘。
  String? _lastRemembered;

  /// 频道列表「10 秒无操作」自动收起的计时器。
  Timer? _channelsHideTimer;
  static const Duration _channelsHideDelay = Duration(seconds: 10);

  /// 硬解设置已应用到播放器的 Future（_playCurrentSource 会等待它，
  /// 确保进入播放前 hwdec 属性已正确设置）。
  Future<void>? _hwdecReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // MediaKit.ensureInitialized() 已在 main() 中调用。
    final Player player = Player();
    _player = player;
    _controller = VideoController(player);
    // 硬件解码：默认关闭（TV 设备兼容性考虑），用户可在「我的」页开启。
    // 需等 AppSettings 加载完成后再设置，确保值正确；_playCurrentSource 会等 _hwdecReady。
    _hwdecReady = _applyHwdecSetting(player);
    // 源播放失败/结束（completed=true）时尝试回退到下一个源。
    _errorSub = player.stream.error.listen((String msg) {
      final String trimmed = msg.trim();
      // 直播源不支持 seek 时 media_kit 会把同一错误拆成多行报出，
      // 都属于非致命（源本身可播，画面会闪一下），整组忽略、不触发回退。
      if (trimmed.contains('Cannot seek in this stream') || trimmed.contains('--force-seekable')) {
        Injection.get<LogService>().info('[LivePlayerWidget] 忽略非致命错误(不影响播放): $trimmed');
        return;
      }
      final String detail = trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
      // 真实 open 失败（非 seek 类）跳过冷却，允许连续打不开的源一路回退。
      _onPlaybackIssue(reason: 'error: $detail', bypassCooldown: true);
    });
    _completedSub = player.stream.completed.listen((bool done) {
      if (done) _onPlaybackIssue(reason: 'completed=true');
    });
    // 记住当前频道可用的源。
    _playingSub = player.stream.playing.listen((value) {
      if (value) _rememberCurrentSource();
    });
    // 出过视频帧（width>0）→ 视为有画面，取消黑屏看门狗。
    _widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0) {
        _playedVideo = true;
        _hangWatchdog?.cancel();
      }
    });
    // 每秒检查「持续缓冲卡死」：playing 且 buffering 连续累计超阈值才回退。
    _bufferStallWatch = Timer.periodic(const Duration(seconds: 1), (_) => _checkBufferStall());
    // 同步频道数与当前选中频道，随后监听上/下键的切换。
    _syncChannels();
    _channelController.addListener(_onChannelChanged);
    HomeNowPlayingController.instance.onSwitchSource = _switchSource;
    HomeNowPlayingController.instance.onShowToast = () {
      if (mounted) _showChannelToast(_channelSourceLabel());
    };
    _restoreLastChannel();
  }

  @override
  void didUpdateWidget(covariant LivePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameChannels(oldWidget.channels, widget.channels)) {
      _syncChannels();
      _openChannel(_channelController.index, force: true);
    }
  }

  /// 两个频道列表是否内容一致（名称 + 源列表逐一比较）。
  bool _sameChannels(List<IptvChannel> a, List<IptvChannel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final IptvChannel x = a[i];
      final IptvChannel y = b[i];
      if (x.name != y.name) return false;
      if (x.sources.length != y.sources.length) return false;
      for (int j = 0; j < x.sources.length; j++) {
        if (x.sources[j] != y.sources[j]) return false;
      }
    }
    return true;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 返回前台不再无条件重开：先做短时健康检测，只有确认播放已损坏才重开，
      // 避免「短暂离开后回来其实还能正常播」也被强制重新加载（闪黑、重新缓冲）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkResumeHealth();
      });
    }
  }

  /// 恢复前台后的播放健康检测（解决 RN/媒体 Surface 被销毁的固有风险）。
  ///
  /// 给播放器一点时间重建 Surface / 恢复解码，随后综合判断：
  /// - [playing] 为 true、出现过视频帧（width>0）、且 position 相对「回前台起点」
  ///   持续推进（说明解码管线仍在出帧）→ 健康，不打扰；
  /// - 否则判定损坏（Surface 可能已销毁 / 解码停滞），对当前源重新 play。
  Future<void> _checkResumeHealth() async {
    final Player? p = _player;
    if (p == null) return;
    final Duration resumePos = p.state.position;
    // 重建 Surface / 恢复解码的缓冲时间。正常播放时 1.5s 内 position 会持续推进。
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || _player != p) return;
    final dynamic s = p.state;
    final bool playing = s.playing;
    final bool hasFrame = (s.width ?? 0) > 0;
    final bool advanced =
        (s.position - resumePos) >= const Duration(milliseconds: 500);
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 恢复前台健康检测 playing=$playing width=${s.width} '
      '位置推进${(s.position - resumePos).inMilliseconds}ms',
    );
    if (!(playing && hasFrame && advanced)) {
      // 确认有问题才重开当前源，且此时无需走 700ms 冷却 / 多源回退。
      await _playCurrentSource();
    }
  }

  /// 启动时恢复上次播放的频道（仍存在则切过去，否则默认首台）。
  Future<void> _restoreLastChannel() async {
    // 默认首台(0)。
    int target = _channelController.index;
    final String? last = await ChannelSourceCache.instance.lastChannelName();
    if (last != null) {
      final int idx = widget.channels.indexWhere((IptvChannel c) => c.name == last);
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
    final String? preferred = await ChannelSourceCache.instance.preferredSourceOf(widget.channels[index].name);
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

  /// 每秒检查「持续缓冲卡死」：仅当 playing 且 buffering 连续累计达阈值才回退，
  /// 一旦缓冲恢复或未在播放即清零，因此正常播放/短暂缓冲不会误杀。
  void _checkBufferStall() {
    if (!mounted) return;
    final dynamic s = _player?.state;
    if (s == null) return;
    final bool playing = s.playing;
    final bool buffering = s.buffering;
    if (playing && buffering) {
      _bufferingAccum += const Duration(seconds: 1);
      if (_bufferingAccum >= _bufferStallThreshold) {
        final String name = _currentChannel()?.name ?? '?';
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 看门狗 持续缓冲卡死 频道$name'
          '源(${_currentSource + 1}) 累计${_bufferingAccum.inSeconds}s '
          'width=${s.width}',
        );
        _bufferingAccum = Duration.zero;
        _onPlaybackIssue(reason: '持续缓冲卡死(${_bufferStallThreshold.inSeconds}s)');
      }
    } else {
      _bufferingAccum = Duration.zero;
    }
  }

  IptvChannel? _currentChannel() {
    if (_currentIndex < 0 || _currentIndex >= widget.channels.length) {
      return null;
    }
    return widget.channels[_currentIndex];
  }

  /// 从持久化读取硬解设置并应用到播放器。
  ///
  /// media_kit v1.x 中 setProperty 是 NativePlayer 的方法，需通过 platform 访问。
  /// mpv 的 hwdec 需在 open 前设置才生效，因此 _playCurrentSource 会等待此 Future。
  Future<void> _applyHwdecSetting(Player player) async {
    await AppSettings.instance.ensureLoaded();
    if (player.platform is! NativePlayer) return;
    final bool enabled = AppSettings.instance.hwdecEnabled;
    await (player.platform as NativePlayer).setProperty('hwdec', enabled ? 'auto' : 'no');
  }

  /// 打开当前频道的当前源。
  Future<void> _playCurrentSource() async {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    // 确保硬解设置已应用到播放器（mpv 的 hwdec 需在 open 前设置才生效）。
    await _hwdecReady;
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _lastOpenAt = DateTime.now();
    _bufferingAccum = Duration.zero; // 新源从零开始累计缓冲
    _startHangWatchdog();
    Injection.get<LogService>().info('[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length})');
    await _player?.open(Media(channel.sources[idx]));
  }

  /// 左下角频道名提示文案：`频道名称 (源 i/N)`。
  String _channelSourceLabel() {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return '';
    final int i = (_currentSource + 1).clamp(1, channel.sources.length);
    return '${channel.name} (源 $i/${channel.sources.length})';
  }

  /// 启动“打开后长时间无画面”看门狗。
  ///
  /// 打开源后 [_hangTimeout]（60 秒）内若既未开始播放、或一直没出现视频帧
  /// （黑屏），则回退下一个源。出现视频帧(width>0)即取消。
  /// 特别注意：黑屏时 stream 的 position 仍可能推进，故**不用 position 作健康信号**。
  void _startHangWatchdog() {
    // 重置健康信号，等待视频帧。
    _playedVideo = false;
    _hangWatchdog?.cancel();
    _hangWatchdog = Timer(_hangTimeout, () {
      if (!mounted) return;
      // 已在使用其它源则忽略。
      if (_player?.state.playlist.index != _currentSource) return;
      final bool playing = _player?.state.playing ?? false;
      final String name = _currentChannel()?.name ?? '?';
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 看门狗到期 频道$name源(${_currentSource + 1}) '
        'playing=$playing buffering=${_player?.state.buffering} '
        'width=${_player?.state.width}',
      );
      if (!playing) {
        _onPlaybackIssue(reason: '打开${_hangTimeout.inSeconds}s后未进入播放');
      } else if (!_playedVideo) {
        _onPlaybackIssue(reason: '打开${_hangTimeout.inSeconds}s后无视频帧(黑屏)');
      }
    });
  }

  /// 左/右键手动切换当前频道的源（循环换向）。
  void _switchSource(int delta) {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int n = channel.sources.length;
    _currentSource = (_currentSource + delta + n) % n;
    Injection.get<LogService>().info('[LivePlayerWidget] 手动切换频道:${channel.name},源(${_currentSource + 1}/$n)');
    _playCurrentSource();
    // 刷新提示并保持可见，便于连续左右切源。
    if (mounted) _showChannelToast(_channelSourceLabel());
  }

  /// 播放失败/结束：循环回退到下一个源。
  ///
  /// 多源时按 1-2-3-4-1-2-… 循环；单源时反复重试同一源 1-1-1-…。
  /// [bypassCooldown] 供真实的 open 失败（如 `Failed to open`）跳过 700ms 冷却，
  /// 使连续打不开的源能一路回退下去，而不是被冷却卡停在当前源。
  Future<void> _onPlaybackIssue({String reason = '', bool bypassCooldown = false}) async {
    if (_handleFailureBusy || !mounted) return;
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    // 刚 open 后立刻来的事件多为旧源残留，忽略，避免误回退。
    if (!bypassCooldown && DateTime.now().difference(_lastOpenAt).inMilliseconds < 700) {
      return;
    }
    _handleFailureBusy = true;
    _currentSource = (_currentSource + 1) % channel.sources.length;
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 切换频道:${channel.name},源'
      '(${_currentSource + 1}/${channel.sources.length})，原因: $reason',
    );
    await _playCurrentSource();
    _handleFailureBusy = false;
    // 刷新左下角里的源序号提示。
    if (mounted) _showChannelToast(_channelSourceLabel());
  }

  /// 左下角显示当前频道名与源序号，30 秒后自动消失。
  /// 使用 ValueNotifier 局部刷新，避免 setState 导致 Video 重建闪烁。
  void _showChannelToast(String name) {
    _toastTimer?.cancel();
    _toastNameVN.value = name;
    // 提示可见时，首页「左/右」由壳层路由为切换源。
    HomeNowPlayingController.instance.toastVisible = true;
    _toastTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _toastNameVN.value = null;
      HomeNowPlayingController.instance.toastVisible = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channelController.removeListener(_onChannelChanged);
    HomeNowPlayingController.instance.onSwitchSource = null;
    HomeNowPlayingController.instance.onShowToast = null;
    HomeNowPlayingController.instance.toastVisible = false;
    _toastTimer?.cancel();
    _toastNameVN.dispose();
    _channelsHideTimer?.cancel();
    _hangWatchdog?.cancel();
    _bufferStallWatch?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
    _widthSub?.cancel();
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
    return BlocListener<AppBloc, AppState>(
      listenWhen: (prev, curr) => prev.hwdecEnabled != curr.hwdecEnabled,
      listener: (context, state) {
        // 运行时切换硬解设置：立即应用到当前播放器（下一个频道/源生效）。
        final Player? p = _player;
        if (p != null && p.platform is NativePlayer) {
          (p.platform as NativePlayer).setProperty('hwdec', state.hwdecEnabled ? 'auto' : 'no');
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 视频始终全屏铺满；fit/aspectRatio 跟随「我的」页的画面显示模式。
          BlocBuilder<AppBloc, AppState>(
            buildWhen: (previous, current) =>
                previous.aspectMode != current.aspectMode,
            builder: (context, state) {
              final VideoAspectMode mode = state.aspectMode;
              return ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: mode.fit,
                  aspectRatio: mode.aspectRatio,
                ),
              );
            },
          ),
          // 右侧频道条：显隐由 showChannels 开关控制（OK 同步 / 菜单键单独呼出）。
          Align(
            alignment: Alignment.centerRight,
            child: BlocBuilder<AppBloc, AppState>(
              buildWhen: (previous, current) => previous.showChannels != current.showChannels,
              builder: (context, state) {
                // 列表处于可见时确保有 30 秒计时（初始显示也算）。
                if (state.showChannels && (mounted && _channelsHideTimer == null)) {
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
          // 左下角频道名提示（30 秒后自动消失），ValueListenableBuilder 局部刷新。
          ValueListenableBuilder<String?>(
            valueListenable: _toastNameVN,
            builder: (context, name, _) {
              if (name == null) return const SizedBox.shrink();
              return Positioned(
                left: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

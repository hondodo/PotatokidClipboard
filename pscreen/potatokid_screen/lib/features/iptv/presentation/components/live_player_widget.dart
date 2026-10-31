import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:pscreen_screen/core/media/video_aspect_mode.dart';
import 'package:pscreen_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_source_cache.dart';
import 'package:pscreen_screen/features/iptv/application/home_now_playing_controller.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';
import 'package:pscreen_screen/features/iptv/application/playback_retry_controller.dart';
import 'package:pscreen_screen/features/iptv/application/playback_watchdog.dart';
import 'package:pscreen_screen/features/iptv/data/datasources/remote/proxy_pool_service.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/channel_bar.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/direction_widget.dart';
import 'package:pscreen_screen/features/time/domain/lunar_calendar.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_days_panel.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_now_panel.dart';

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

  /// 打开频道请求的序号（见 `_openChannel`）：用于丢弃 await 期间已过期的打开请求。
  int _openSeq = 0;

  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 播放失败重试状态机（共享包 `PlaybackRetryController`）：700ms 冷却、
  /// 多源循环回退、一轮判定与 1→2→4→8s 退避都在它内部；换路由（代理）
  /// 经 `retryWithRoute` 回调注入，失败现场上报经 `onEnterRetry` 注入。
  late final PlaybackRetryController _retry;

  /// 媒体类型判定（共享包 `MediaKindProbe`）：只看真实轨道区分音频台/视频台，
  /// 结论与证据（[_playedVideo] / [_audioParamsReady]）都读它。
  late final MediaKindProbe _probe;

  /// 「打开后长时间无画面」看门狗（共享包 `PlaybackWatchdog`）：
  /// 超时取 [_hangTimeoutNow]，到期按媒体类型分流结算，
  /// 坏源经 [_onPlaybackIssue] 进入重试。
  late final PlaybackWatchdog _watchdog;

  /// 当前正在播放的源序号（真值在重试状态机里，见 `PlaybackRetryController.sourceIndex`）。
  int get _currentSource => _retry.sourceIndex;

  /// 媒体类型判定结论（见 `MediaKindProbe.kind`）。
  MediaKind get _mediaKind => _probe.kind;

  /// 黑屏判定：是否出现过真实视频帧（width>0）。
  bool get _playedVideo => _probe.playedVideo;

  /// 音频输出参数是否已就绪（音频节目「已出声音」的证据）。
  bool get _audioParamsReady => _probe.audioParamsReady;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  /// 打开源后迟迟无画面/无声音的看门狗超时（解决“连了很久没反应”）。
  static const Duration _hangTimeout = Duration(seconds: 60);

  /// 代理重试时的对应超时：免费代理普遍慢/不通，缩短以便尽快换下一个。
  static const Duration _proxyHangTimeout = Duration(seconds: 20);

  /// 当前生效的看门狗超时（代理模式更短），供 [PlaybackWatchdog] 取值。
  Duration get _hangTimeoutNow => _proxyUrl == null ? _hangTimeout : _proxyHangTimeout;

  /// 进入播放即推进看门狗结算。
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _widthSub;

  /// 当前源是否已记录过一次「忽略音频解码错误」，避免同一错误反复刷日志。
  bool _audioDecodeErrorLogged = false;

  /// 声条是否跳动（只由 [_syncBarsActive] 更新）。
  ///
  /// 用 ValueNotifier 而不是 setState：播放状态变化很频繁，setState 会把上层
  /// [Video] 一起重建，切台时画面会闪。
  final ValueNotifier<bool> _barsActiveVN = ValueNotifier<bool>(false);

  /// 轨道 / 音频参数订阅（供共享判定器 [_probe] 取证）。
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<AudioParams>? _audioParamsSub;

  /// 「持续缓冲卡死」检测：playing 且 buffering 连续累计超阈值才回退。
  Timer? _bufferStallWatch;
  Duration _bufferingAccum = Duration.zero;
  static const Duration _bufferStallThreshold = Duration(seconds: 60);

  /// 代理重试时的卡死阈值（同上，缩短）。
  static const Duration _proxyStallThreshold = Duration(seconds: 20);

  /// 当前生效的卡死阈值（代理模式更短）。
  Duration get _stallThresholdNow => _proxyUrl == null ? _bufferStallThreshold : _proxyStallThreshold;

  /// 最近一次记住的「频道|源URL」，避免重复写盘。
  String? _lastRemembered;

  /// 频道列表「10 秒无操作」自动收起的计时器。
  Timer? _channelsHideTimer;
  static const Duration _channelsHideDelay = Duration(seconds: 5);

  /// 硬解设置已应用到播放器的 Future（_playCurrentSource 会等待它，
  /// 确保进入播放前 hwdec 属性已正确设置）。
  Future<void>? _hwdecReady;

  /// 当前正在使用的代理（`http://ip:port`）；null 表示直连。
  ///
  /// 「代理重试」开启时：直连失败会设上代理重试同一个源，成功后沿用；
  /// 代理也失败则换下一个代理继续试，试满 [_maxProxyAttempts] 次仍不行才回退到下一个源。
  String? _proxyUrl;

  /// 当前源已尝试过的代理个数（换源/换台时清零）。
  int _proxyAttempts = 0;

  /// 单个源最多用几个代理去试（免费代理可用率低，多试几个才有机会）。
  static const int _maxProxyAttempts = 3;

  /// 已写入 mpv 的 `http-proxy` 值（null 表示还没写过），用于避免重复设置。
  String? _appliedProxy;

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
    // ---- 共享包三件套（媒体判定 / 看门狗 / 重试状态机），先建再挂订阅 ----
    _probe = MediaKindProbe(onChanged: _onProbeChanged);
    _watchdog = PlaybackWatchdog(
      probe: _probe,
      isPlaying: () => _player?.state.playing ?? false,
      onIssue: (String reason) => _onPlaybackIssue(reason: reason),
      timeoutOf: () => _hangTimeoutNow,
      onTimeout: () {
        // 到期现场最有诊断价值：一并记下播放器状态。
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 看门狗到期 频道${_currentChannel()?.name ?? '?'}源(${_currentSource + 1}) '
          '媒体类型=${_mediaKind.name} playing=${_player?.state.playing ?? false} '
          'buffering=${_player?.state.buffering} width=${_player?.state.width}',
        );
      },
      onAudioEstablished: () {
        // 音频节目确有输出 = 该频道可用：清理失效源的连续失败计数清零。
        final IptvChannel? channel = _currentChannel();
        if (channel != null) ChannelFailureGuard.instance.recordSuccess(channel.name);
      },
    );
    _retry = PlaybackRetryController(
      sourceCount: () => _currentChannel()?.sources.length ?? 0,
      open: (int sourceIndex) => _playCurrentSource(),
      // 失败现场（必须在换源 / 换代理之前）：上报 play_retry + 统计失效源。
      onEnterRetry: (String reason) {
        _reportPlayback('play_retry', reason: reason);
        _recordInvalidSourceFailure(reason);
      },
      // 换路由 = 代理池重试同一源（见 [_retryWithRoute]）。
      retryWithRoute: _retryWithRoute,
      onBackoff: _onRoundBackoff,
      onSourceChanged: (int sourceIndex, String reason) {
        final IptvChannel? channel = _currentChannel();
        if (channel != null) {
          Injection.get<LogService>().info(
            '[LivePlayerWidget] 切换频道:${channel.name},源'
            '(${sourceIndex + 1}/${channel.sources.length})，原因: $reason',
          );
        }
        // 已换到下一个源：刷新左下角的源序号提示。
        if (mounted) _showChannelToast(_channelSourceLabel(withNumber: true));
      },
      isActive: () => mounted,
    );
    // 源播放失败/结束（completed=true）时尝试回退到下一个源。
    _errorSub = player.stream.error.listen((String msg) {
      final String trimmed = msg.trim();
      // 直播源不支持 seek 时 media_kit 会把同一错误拆成多行报出，
      // 都属于非致命（源本身可播，画面会闪一下），整组忽略、不触发回退。
      if (trimmed.contains('Cannot seek in this stream') || trimmed.contains('--force-seekable')) {
        Injection.get<LogService>().info('[LivePlayerWidget] 忽略非致命错误(不影响播放): $trimmed');
        return;
      }
      // 音轨解码失败但画面正常：重开整个流只会黑屏一下、声音中断，
      // 单源频道还会陷入「重开 → 报错 → 重开」的循环（实测 1~2 秒一次）。
      // 这类源的毛病只在音轨，画面既然已经正常，就让它继续播。
      if (_isAudioDecodeError(trimmed) && _isPlaybackHealthy()) {
        if (!_audioDecodeErrorLogged) {
          _audioDecodeErrorLogged = true;
          Injection.get<LogService>().info(
            '[LivePlayerWidget] 忽略音频解码错误(画面正常，不重开该源): $trimmed',
          );
        }
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
      if (value) {
        // 真的开始播放了：本轮退避清零，下次再坏重新从 1 秒起算。
        _retry.resetRound();
        _rememberCurrentSource();
      }
      // 音频节目的「已出声」证据之一；判定挂起时据此立即结算看门狗。
      _watchdog.notifyState();
      // 真的进入播放了 → 声条可以开始跳。
      _syncBarsActive();
      // 进入播放是成功证据之一（视频仍需画面帧配合，见方法内判据）。
      if (value) _maybeReportPlaybackOk();
    });
    // 出过视频帧（width>0）→ 视为有画面，取消黑屏看门狗。
    _widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0) {
        // 出画面：判定为视频节目（音频判定到此推翻、兜底窗口取消），
        // 并解除「打开后无画面」看门狗。
        _probe.handleWidth(w);
        _watchdog.cancel();
        // 出画面说明该频道可用：本轮「清理失效源」的连续失败计数清零。
        final IptvChannel? channel = _currentChannel();
        if (channel != null) {
          ChannelFailureGuard.instance.recordSuccess(channel.name);
        }
        // 有真实画面 = 视频节目播放成功。
        _maybeReportPlaybackOk();
      }
    });
    // 运行时区分「音频节目 / 视频节目」：只看真实轨道，不看地址与名称。
    // 判定规则（排除 auto/no 伪轨与封面图、空表不作数、音频立即下结论、
    // 兜底窗口）都在共享包 [MediaKindProbe] 里；结论变化经 [_onProbeChanged]
    // 刷新界面并记日志。轨道表是判定主入口。
    _tracksSub = player.stream.tracks.listen((Tracks tracks) {
      _probe.handleTracks(tracks);
      // 判定可能刚落定 → 推进挂起的看门狗结算。
      _watchdog.notifyState();
    });
    // 音频输出参数就绪 → 音频节目的「确实出声了」证据。
    _audioParamsSub = player.stream.audioParams.listen((AudioParams p) {
      if (p.channelCount != null || p.sampleRate != null || p.format != null) {
        _probe.handleAudioParams(p);
        _watchdog.notifyState();
        // 音频输出参数就绪 → 确实在出声，声条开始跳。
        _syncBarsActive();
        // 音频节目「已出声」的成功证据之一。
        if (_mediaKind == MediaKind.audio) _maybeReportPlaybackOk();
      }
    });
    // 每秒检查「持续缓冲卡死」：playing 且 buffering 连续累计超阈值才回退。
    _bufferStallWatch = Timer.periodic(const Duration(seconds: 1), (_) => _checkBufferStall());
    // 同步频道数与当前选中频道，随后监听上/下键的切换。
    _syncChannels();
    // 「选中」立即刷新界面，「播放提交」延迟换源（两者分开的原因见控制器注释）。
    _channelController.addListener(_onChannelSelected);
    _channelController.onPlayCommit.addListener(_onPlayCommit);
    HomeNowPlayingController.instance.onSwitchSource = _switchSource;
    HomeNowPlayingController.instance.onToggleChannelPanel = _toggleChannelPanel;
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
    // 频道列表真值同步给上报/命令解析用的查询服务（initState 与刷新均经此处）。
    ChannelInfoProvider.instance.setChannels(widget.channels);
  }

  /// 选中变化（**立即**）：只刷新界面——显示频道列表 + 左下角频道名，
  /// 这里**不** open，播放交给 [_onPlayCommit] 延迟提交。
  /// 长按连切时选中照旧飞快跟手，但不会每 80ms 就换一次流。
  void _onChannelSelected() {
    // 换台算一次列表操作：显示列表并重置 30 秒计时。
    _markChannelsActivity();
    // 频道名立即跟着选中走（此时源序号按首源显示，提交后会用真实源号再刷一次）。
    if (mounted) _showChannelToast(_selectedChannelLabel());
  }

  /// 播放提交（停止切换 `LiveChannelController.commitDelay` 后）：真正换源。
  void _onPlayCommit() {
    _openChannel(_channelController.index);
    // 记录当前频道，下次启动据此恢复（写盘也一并挪到这里，避免长按时反复写）。
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
  /// - [playing] 为 true、且 position 相对「回前台起点」持续推进 → 健康，不打扰；
  /// - 视频节目还要求出现过视频帧（width>0）；音频节目（广播台）本就没有视频帧，
  ///   不能用它判健康，否则每次回前台都会无谓重载；
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
    final bool advanced = (s.position - resumePos) >= const Duration(milliseconds: 500);
    // 只有「判定为音频」才放宽视频帧要求；unknown 仍按视频严格处理（默认视频）。
    final bool healthy = playing && advanced && (_mediaKind == MediaKind.audio || hasFrame);
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 恢复前台健康检测 playing=$playing width=${s.width} '
      '媒体类型=${_mediaKind.name} '
      '位置推进${(s.position - resumePos).inMilliseconds}ms',
    );
    if (!healthy) {
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
      _channelController.select(target); // 立即提交 → _onPlayCommit → 打开并记录
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

  /// 首页 OK 键：显示/隐藏「左下角频道信息 + 右侧频道列表」。
  /// 两者都可见时统一隐藏；否则统一显示并重置各自的自动隐藏计时。
  void _toggleChannelPanel() {
    if (!mounted) return;
    final bool toastVisible = _toastNameVN.value != null;
    final bool listVisible = context.read<AppBloc>().state.showChannels;
    if (toastVisible && listVisible) {
      _toastTimer?.cancel();
      _toastNameVN.value = null;
      _channelsHideTimer?.cancel();
      _channelsHideTimer = null;
      context.read<AppBloc>().add(const SetChannels(false));
    } else {
      _showChannelToast(_channelSourceLabel(withNumber: true));
      _markChannelsActivity();
    }
  }

  Future<void> _openChannel(int index, {bool force = false}) async {
    if (index < 0 || index >= widget.channels.length) return;
    final bool changed = index != _currentIndex;
    if (!force && !changed) return;
    _currentIndex = index;
    // 换台是全新一轮试源：源序号回 0、退避从 1 秒重新起算，
    // 并推进世代号，让退避中的过期回退自动作废。
    _retry.resetForChannel(0);
    // 本次打开请求的序号：await 期间若又切了台，过期请求直接丢弃，
    // 避免两次 open 交错（重复 open/stop 正是长按卡顿的成因）。
    final int seq = ++_openSeq;
    // 换台后重新从直连开始试（换台失败才会再走代理）。
    _proxyUrl = null;
    _proxyAttempts = 0;
    // 优先从上次可用源起播（记忆的 URL 已不在此频道则回落首源）。
    final String? preferred = await ChannelSourceCache.instance.preferredSourceOf(widget.channels[index].name);
    if (!mounted || seq != _openSeq) return;
    if (preferred != null) {
      final int idx = widget.channels[index].sources.indexOf(preferred);
      if (idx >= 0) _retry.sourceIndex = idx;
    }
    if (mounted) setState(() {});
    if (changed || force) {
      // 切台时抑制旧流的 error/completing 干扰。
      _retry.setBusy(true);
      await _playCurrentSource();
      _retry.setBusy(false);
      _showChannelToast(_channelSourceLabel(withNumber: true));
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
      final Duration threshold = _stallThresholdNow;
      if (_bufferingAccum >= threshold) {
        final String name = _currentChannel()?.name ?? '?';
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 看门狗 持续缓冲卡死 频道$name'
          '源(${_currentSource + 1}) 累计${_bufferingAccum.inSeconds}s '
          'width=${s.width}',
        );
        _bufferingAccum = Duration.zero;
        _onPlaybackIssue(reason: '持续缓冲卡死(${threshold.inSeconds}s)');
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

  /// 播放状态上报（**纯观测**：只读播放器当前状态，不参与 open/回退/重试决策；
  /// DI 未就绪等任何异常自行吞掉，绝不影响播放链路）。
  ///
  /// 防刷屏（每源去重 / retry 限流 / ok 连发丢弃）由
  /// [ReportingService.notifyPlayback] 内部完成，这里只负责如实调用。
  void _reportPlayback(String state, {String reason = ''}) {
    try {
      final IptvChannel? channel = _currentChannel();
      if (channel == null || channel.sources.isEmpty) return;
      final int idx = _currentSource.clamp(0, channel.sources.length - 1);
      Injection.get<ReportingService>().notifyPlayback(
        state,
        channel: channel.name,
        sourceIndex: idx + 1,
        sourceTotal: channel.sources.length,
        sourceUrl: channel.sources[idx],
        reason: reason,
        // failedRounds 从 0 计：对外语义是「正在尝试第几轮」（1 起）。
        round: _retry.failedRounds + 1,
        viaProxy: _proxyUrl != null,
        elapsed: DateTime.now().difference(_lastOpenAt),
      );
    } catch (_) {
      // 上报不可用不影响播放。
    }
  }

  /// 播放成功判定（按节目类型区分标准，与看门狗一致）：
  /// 视频要出过真实画面帧（width>0），音频要已进入播放且类型已判定为音频。
  void _maybeReportPlaybackOk() {
    final bool playing = _player?.state.playing ?? false;
    if (_playedVideo || (_mediaKind == MediaKind.audio && playing)) {
      _reportPlayback('play_ok');
    }
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

  /// 是否为「音轨解码失败」类错误（画面可能完全正常）。
  static bool _isAudioDecodeError(String msg) =>
      msg.contains('Error decoding audio') || msg.contains('Failed to decode audio');

  /// 画面是否已经健康：出过真实视频帧、已判定为「有视频轨的节目」、或已在播放。
  ///
  /// 只有这种情况下的音轨报错才值得忽略。连视频都没起来的源仍按原逻辑回退，
  /// 交给看门狗与回退机制处理，避免「音轨坏 = 整个源不可用」的误判反过来漏掉真坏源。
  bool _isPlaybackHealthy() =>
      _playedVideo ||
      _mediaKind == MediaKind.video ||
      (_player?.state.playing ?? false);

  /// 打开当前频道的当前源。
  Future<void> _playCurrentSource() async {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    // 确保硬解设置已应用到播放器（mpv 的 hwdec 需在 open 前设置才生效）。
    await _hwdecReady;
    // 代理也需在 open 前设置（只影响之后打开的流）。
    await _applyProxySetting(_proxyUrl);
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _lastOpenAt = DateTime.now();
    // 刷新重试状态机的 700ms 冷却基准。
    _retry.markOpen();
    // 每次 open 重新允许记录一次「忽略音频解码错误」。
    _audioDecodeErrorLogged = false;
    _bufferingAccum = Duration.zero; // 新源从零开始累计缓冲
    // 换源后媒体类型重新判定：地址/名称都不作依据，只看新源的真实轨道。
    _probe.reset();
    // 此刻 playing 还是上一个源的值，声条直接停掉（新源真正出声再跳）。
    _barsActiveVN.value = false;
    _watchdog.arm();
    try {
      String source = channel.sources[idx];
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length}) $source'
        '${_proxyUrl == null ? '' : '（代理 $_proxyUrl）'}',
      );
      await _player?.open(Media(channel.sources[idx]));
      _reportPlayback('play_start');
    } catch (e) {
      Injection.get<LogService>().error(
        '[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length}) 失败: $e',
      );
    }
  }

  /// 媒体类型判定结论变化（共享判定器 [_probe] 的 onChanged 回调）：
  /// 刷新界面（音频界面要显示/淡出收音机层）并记一条判定日志。
  ///
  /// 必须在判定回调里 setState：这些回调不经过 build，
  /// 不 setState 的话音频界面要等到别的重建时机才出现。
  void _onProbeChanged(MediaKind kind) {
    if (mounted) setState(() {});
    if (kind != MediaKind.unknown) {
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 媒体类型判定:${kind == MediaKind.audio ? '音频' : '视频'}节目 '
        '频道${_currentChannel()?.name ?? '?'}源(${_currentSource + 1})',
      );
    }
    _syncBarsActive();
  }

  /// 声条是否跳动：只有**已经断定是音频、而且确实出声了**才跳。
  ///
  /// - [unknown]（还在连接）或视频节目 → 不跳。这些情况下广播界面要么黑屏、
  ///   要么根本不可见，跳了只是白白逐帧重绘；
  /// - 音频且已出声（进入播放 / 音频输出参数就绪）→ 跳。
  ///
  /// 音频的判定由轨道表立刻给出，所以这里基本不会出现「画面在播、声条却不跳」的延迟。
  void _syncBarsActive() {
    final bool outputReady = _audioParamsReady || (_player?.state.playing ?? false);
    final bool active = _mediaKind == MediaKind.audio && outputReady;
    if (_barsActiveVN.value != active) _barsActiveVN.value = active;
  }

  /// 设置/清除 mpv 的 HTTP 代理（`http-proxy`）。
  ///
  /// media_kit 的 setProperty 不返回 mpv 的错误码，故设置后**读回校验**：
  /// 读回值与写入值一致 → 说明 mpv 认这项属性（日志打「已生效」）；
  /// 不一致 → 说明当前 mpv 不支持运行时改代理（日志打警告）。
  /// 与上次相同的值会跳过，避免每次起播都重复设置/打日志。
  Future<void> _applyProxySetting(String? proxy) async {
    final String value = proxy ?? '';
    if (_appliedProxy == value) return;
    _appliedProxy = value;
    final Player? p = _player;
    if (p == null || p.platform is! NativePlayer) return;
    try {
      final NativePlayer native = p.platform as NativePlayer;
      await native.setProperty('http-proxy', value);
      final String readback = await native.getProperty('http-proxy');
      if (readback == value) {
        Injection.get<LogService>().info('[LivePlayerWidget] http-proxy 已生效: ${value.isEmpty ? '(直连)' : value}');
      } else {
        Injection.get<LogService>().warn('[LivePlayerWidget] http-proxy 设置未生效: 期望"$value" 实际"$readback"');
      }
    } catch (e) {
      Injection.get<LogService>().warn('[LivePlayerWidget] 设置 http-proxy 失败: $e');
    }
  }

  /// 频道在列表中的显示序号：从 1 开始，按频道总数的位数左侧补零，
  /// 与右侧频道列表（[ChannelBar]）的序号规则完全一致。
  String _channelNumber(int index) {
    final int total = widget.channels.length;
    final int width = total <= 1 ? 1 : total.toString().length;
    return (index + 1).toString().padLeft(width, '0');
  }

  /// 左下角频道名提示文案：`频道名称\n(源 i/N)`,如果要分割，可以用\n来切分。
  ///
  /// [withNumber] 为 true 时在频道名前加显示序号（供左下角提示用，
  /// 音频整屏 [_AudioNowPlaying] 仍用不带序号的版本）。
  String _channelSourceLabel({bool withNumber = false}) {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return '';
    final int i = (_currentSource + 1).clamp(1, channel.sources.length);
    final String prefix = withNumber ? '${_channelNumber(_currentIndex)} ' : '';
    return '$prefix${channel.name}\n源 $i/${channel.sources.length}';
  }

  /// 左下角提示文案（按**选中**频道算），供选中瞬间立即回显频道名。
  ///
  /// 此刻还没提交播放、源号未知，先按首源显示；提交后 `_openChannel` 会用
  /// [_channelSourceLabel] 按真实源号再刷一次。文案带频道显示序号。
  String _selectedChannelLabel() {
    final int index = _channelController.index;
    if (index < 0 || index >= widget.channels.length) return '';
    final IptvChannel channel = widget.channels[index];
    final String name = '${_channelNumber(index)} ${channel.name}';
    if (channel.sources.isEmpty) return name;
    return '$name\n源 1/${channel.sources.length}';
  }

  /// 左/右键手动切换当前频道的源（循环换向）。
  void _switchSource(int delta) {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int n = channel.sources.length;
    // 手动换源是用户主动重试：换源 + 本轮退避清零，并作废退避中的过期回退。
    _retry.setSource((_currentSource + delta + n) % n);
    Injection.get<LogService>().info('[LivePlayerWidget] 手动切换频道:${channel.name},源(${_currentSource + 1}/$n)');
    _playCurrentSource();
    // 刷新提示并保持可见，便于连续左右切源。
    if (mounted) _showChannelToast(_channelSourceLabel(withNumber: true));
  }

  /// 播放失败/结束/看门狗到期：交给共享重试状态机
  /// （冷却过滤 → 失败现场上报 → 换路由[代理]重试同一源 → 一轮退避 → 循环换源，
  /// 见 [PlaybackRetryController]）。
  void _onPlaybackIssue({String reason = '', bool bypassCooldown = false}) {
    unawaited(_retry.handleIssue(reason: reason, bypassCooldown: bypassCooldown));
  }

  /// 「换路由重试同一个源」= 代理池（状态机的 `retryWithRoute` 回调）：
  /// 失败发生在代理上先换下一个代理；直连失败或代理还没试满则挑一个
  /// **探测可用**的代理重开**同一个源**（探测能挡住「代理能连上但对这个源
  /// 返回错误页」这类无效代理）。
  ///
  /// 返回 true = 已换代理重开同一源（状态机到此为止）；
  /// 返回 false = 没有可用代理，由状态机继续走换源回退。
  Future<bool> _retryWithRoute(int failedIndex, String reason) async {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return false;
    final int idx = failedIndex.clamp(0, channel.sources.length - 1);
    final String failedUrl = channel.sources[idx];
    // 第一段：这次失败发生在代理上 → 换下一个代理继续试同一个源。
    if (_proxyUrl != null) {
      Injection.get<LogService>().info('[LivePlayerWidget] 代理未成功，换下一个: $_proxyUrl，原因: $reason');
      _proxyUrl = null;
    }
    // 第二段：挑一个探测可用的代理重试同一个源。
    if (AppSettings.instance.proxyRetryEnabled && _proxyAttempts < _maxProxyAttempts) {
      final String? proxy = await ProxyPoolService.instance.nextUsableProxy(targetUrl: failedUrl);
      // 等待探测期间可能已切台/切源，需复核。
      if (proxy != null && mounted && _currentChannel()?.name == channel.name) {
        _proxyAttempts++;
        _proxyUrl = proxy;
        _retry.sourceIndex = idx;
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 改用代理重试(第$_proxyAttempts次):${channel.name},'
          '源(${idx + 1}/${channel.sources.length}) 代理=$proxy，原因: $reason',
        );
        await _playCurrentSource();
        if (mounted) _showChannelToast(_channelSourceLabel(withNumber: true));
        return true;
      }
      Injection.get<LogService>().info('[LivePlayerWidget] 未找到可用代理（已尝试 $_proxyAttempts 次），回退下一个源');
    }
    // 代理都没救活（或未开启）→ 交给状态机回退到下一个源，重新从直连开始。
    _proxyAttempts = 0;
    return false;
  }

  /// 该频道所有源都各试过一次 = 一轮失败（状态机的 `onBackoff` 回调）：
  /// 退避 1→2→4→8s 后再进下一轮，避免「全源都打不开」时以 mpv 报错的速度
  /// （实测 20~140ms）不停 open/失败，每个 open 都要重建解码器，盒子会持续抖动。
  void _onRoundBackoff(int round, Duration wait) {
    final IptvChannel? channel = _currentChannel();
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 频道${channel?.name ?? '?'} 全部 ${channel?.sources.length ?? 0} 个源都打不开，'
      '第$round轮，${wait.inMilliseconds}ms 后重试',
    );
  }

  /// 失败现场统计入口（状态机 `onEnterRetry` 回调）：在换源/换路由之前调用，
  /// 读到的正是本次失败的源。
  void _recordInvalidSourceFailure(String reason) {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _recordInvalidFailure(channel, channel.sources[idx], reason);
  }

  /// 「清理失效源」开启时统计连续失败：达阈值会先探测确认（区分网络原因），
  /// 确认失效后由 [ChannelFailureGuard] 通知 IptvBloc 重新过滤频道列表。
  void _recordInvalidFailure(IptvChannel channel, String failedUrl, String reason) {
    if (!AppSettings.instance.removeInvalidSources) return;
    ChannelFailureGuard.instance.recordFailure(
      channelName: channel.name,
      sourceUrl: failedUrl,
      reason: reason,
      channelSources: channel.sources,
    );
  }

  /// 左下角显示当前频道名与源序号，30 秒后自动消失。
  /// 使用 ValueNotifier 局部刷新，避免 setState 导致 Video 重建闪烁。
  void _showChannelToast(String name) {
    _toastTimer?.cancel();
    _toastNameVN.value = name;
    _toastTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _toastNameVN.value = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channelController.removeListener(_onChannelSelected);
    _channelController.onPlayCommit.removeListener(_onPlayCommit);
    HomeNowPlayingController.instance.onSwitchSource = null;
    HomeNowPlayingController.instance.onToggleChannelPanel = null;
    _toastTimer?.cancel();
    _toastNameVN.dispose();
    _barsActiveVN.dispose();
    _channelsHideTimer?.cancel();
    _watchdog.dispose();
    _probe.dispose();
    _bufferStallWatch?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
    _widthSub?.cancel();
    _tracksSub?.cancel();
    _audioParamsSub?.cancel();
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
                previous.aspectMode != current.aspectMode ||
                previous.backgroundPlayback != current.backgroundPlayback,
            builder: (context, state) {
              final VideoAspectMode mode = state.aspectMode;
              return ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: mode.fit,
                  aspectRatio: mode.aspectRatio,
                  // 「后台播放」开关（默认关）：关闭时保持 media_kit 默认行为——退到后台即暂停；
                  // 开启后不暂停，安卓退到后台/息屏时声音继续播。
                  pauseUponEnteringBackgroundMode: !state.backgroundPlayback,
                ),
              );
            },
          ),
          // 音频节目（广播台）没有画面，纯黑底上居中显示收音机图标 + 频道名。
          // 不可交互（IgnorePointer），不影响遥控器按键与频道条。
          Positioned.fill(
            child: IgnorePointer(
              child: _AudioNowPlaying(
                label: _channelSourceLabel(),
                // 只在下结论为音频时显示：[unknown]（还在连接/未判定）保持黑屏，
                // 结论由轨道表立刻给出（见 _tracksSub），不等判定窗口。
                visible: _mediaKind == MediaKind.audio,
                barsActive: _barsActiveVN,
              ),
            ),
          ),
          // 右侧频道条：显隐由 showChannels 开关控制（首页 OK 键切换 / 换台时自动显示）。
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
                    // 频道条直接监听「选中」通知：高亮与滚动跟随必须**立即**，
                    // 不能等播放提交（_openChannel 的 setState）——那是 400ms 之后的事。
                    child: ListenableBuilder(
                      listenable: _channelController,
                      builder: (context, _) => ChannelBar(
                        channels: widget.channels,
                        selectedIndex: _channelController.index,
                        onChanged: _channelController.select,
                        visible: state.showChannels,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 数字键直选频道时的回显：左上角显示已按下的数字（`1`/`12`/`123`），
          // 号码超出范围时改显示提示文案，让用户随时知道自己按到了第几号。
          const Positioned(left: 24, top: 84, child: _ChannelNumberOverlay()),
          // 左下角频道名提示（30 秒后自动消失），ValueListenableBuilder 局部刷新。
          ValueListenableBuilder<String?>(
            valueListenable: _toastNameVN,
            builder: (context, text, _) {
              if (text == null) return const SizedBox.shrink();
              Color textColor = Colors.white;
              String name = text;
              String sourceTips = '';
              if (text.contains('\n')) {
                var labels = text.split('\n');
                if (labels.isNotEmpty) {
                  name = labels.first;
                }
                if (labels.length > 1) {
                  sourceTips = labels[1];
                }
              }
              return Positioned(
                left: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          WeatherNowPanel(),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(color: textColor, fontSize: 16)),
                              Text(sourceTips, style: TextStyle(color: textColor, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Column(
                            children: [
                              DirectionWidget(hotUp: true, hotDown: true, size: 52),
                              Text('更换频道', style: TextStyle(color: textColor, fontSize: 14)),
                            ],
                          ),
                          SizedBox(width: 8),
                          Column(
                            children: [
                              DirectionWidget(hotLeft: true, hotRight: true, size: 52),
                              Text('更换播放源', style: TextStyle(color: textColor, fontSize: 14)),
                            ],
                          ),
                          SizedBox(width: 8),
                          _ClockPanel(color: textColor),
                          SizedBox(width: 8),
                          WeatherDaysPanel(),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 数字键直选频道的输入回显：显示已按下的数字（`1` / `12` / `123`），
/// 号码超出范围时改显示「频道号超出范围」提示。
///
/// 只监听 [ChannelNumberInputController]，局部刷新，不影响播放器重建。
class _ChannelNumberOverlay extends StatelessWidget {
  const _ChannelNumberOverlay();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChannelNumberInputController.instance,
      builder: (context, _) {
        final ChannelNumberInputController input = ChannelNumberInputController.instance;
        if (!input.visible) return const SizedBox.shrink();
        final bool outOfRange = input.outOfRange;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            outOfRange ? 'iptv_channel_number_out_of_range'.tr() : input.digits,
            style: TextStyle(
              color: Colors.white,
              fontSize: outOfRange ? 24 : 56,
              fontWeight: FontWeight.bold,
              height: 1.1,
              letterSpacing: outOfRange ? 0 : 4,
              fontFeatures: outOfRange ? null : const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// 音频节目（广播台）的「正在播放」整屏。
///
/// 排版（纵向居中，自下而上铺氛围层）：
/// ```text
///            18:42:07            ← 大号时间 + 日期/农历
///                📻              ← 收音机图标
///            甘肃新闻综合          ← 频道名
///              源 1/2
///      ☁️ 26° 湛江  今 28°/22° …   ← 天气：当前 + 未来 3 天
///   ▁▃▅▇█▆▄▂▁▃▅▇█▆▄▂▁▃▅▇ (跳动声条，贴底氛围层)
/// ```
///
/// **显示条件**：只在判定为音频时显示。[unknown]（还没拿到轨道表、仍在连接）
/// 保持黑屏；音频的判定由轨道表立刻给出，不用等兜底窗口。
///
/// 显隐用淡入淡出避免切台瞬间突兀，且始终留在树上以便做过渡动画。
class _AudioNowPlaying extends StatelessWidget {
  const _AudioNowPlaying({required this.label, required this.visible, required this.barsActive});

  /// 频道名与源序号（形如 `甘肃新闻综合\n源 1/2`，由
  /// `LivePlayerWidget._channelSourceLabel()` 生成）。
  final String label;

  /// 是否显示。
  final bool visible;

  /// 声条是否跳动。与 [visible] 分开：连接中（unknown）界面已显示，
  /// 但还没出声，声条不跳，避免造成「已经在播」的错觉。
  final ValueListenable<bool> barsActive;

  @override
  Widget build(BuildContext context) {
    final List<String> lines = label.split('\n');
    final String name = lines.isNotEmpty ? lines.first : label;
    final String sourceTips = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    // 以短边为基准缩放，TV 大屏与手机上都协调。
    final Size size = MediaQuery.sizeOf(context);
    final double shortSide = size.shortestSide;
    final double iconSize = (shortSide * 0.11).clamp(56.0, 132.0);
    final double nameSize = (shortSide * 0.042).clamp(24.0, 54.0);
    final double tipsSize = (shortSide * 0.026).clamp(16.0, 32.0);
    final double timeSize = (shortSide * 0.075).clamp(48.0, 92.0);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 氛围层：贴底的跳动声条。低透明度，只做背景，不抢前景信息。
          // 用 ValueListenableBuilder 局部刷新：播放状态变化只重建这一层，
          // 不会牵连上面的 [Video]。
          Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              child: SizedBox(
                height: shortSide * 0.3,
                width: double.infinity,
                child: ValueListenableBuilder<bool>(
                  valueListenable: barsActive,
                  builder: (BuildContext context, bool active, Widget? _) => _EqualizerBars(active: active),
                ),
              ),
            ),
          ),
          // 前景信息：时间 → 频道 → 天气，纵向居中。
          Center(
            child: Column(
              //mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                const SizedBox(height: 32),
                _ClockPanel(color: Colors.white, timeSize: timeSize, horizontalSize: true),
                const SizedBox(height: 16),
                Column(
                  children: [
                    Icon(Icons.radio_rounded, size: iconSize, color: Colors.white.withValues(alpha: 0.92)),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: nameSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),

                    if (sourceTips.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        sourceTips,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: tipsSize),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Transform.scale(
                  scale: 2.0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[WeatherNowPanel(), SizedBox(width: 24), WeatherDaysPanel()],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 跳动声条（音频整屏的背景氛围层）。
///
/// **是模拟动画，不是真实频谱**：取真实频谱需要从原生侧拿 PCM 数据做 FFT，
/// 而 media_kit/mpv 没有把这层暴露给 Dart；对「正在播放」的氛围表达，
/// 多条不同频率正弦叠加已经足够，且零依赖、可控开销。
///
/// [active] 为 false 时停掉动画：该层始终留在树上（做淡入淡出），
/// 不主动停会导致「连接中/不播音频」时也在后台逐帧空转。
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.active});

  /// 是否让声条跳动（由 `LivePlayerWidget._barsActiveVN` 驱动：
  /// 确认是音频节目且确实出声了才为 true）。
  final bool active;

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EqualizerBarsPainter(animation: _controller, color: Colors.white.withValues(alpha: 0.22)),
    );
  }
}

/// 声条绘制：把时间轴映射成每条柱子的高度。
class _EqualizerBarsPainter extends CustomPainter {
  _EqualizerBarsPainter({required this.animation, required this.color}) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  /// 柱子数量：够密才有氛围，又不至于在低端盒子上浪费绘制。
  static const int _barCount = 44;

  /// 最低高度占比：留一条视觉基线，避免柱子「归零」后整排消失。
  static const double _minRatio = 0.06;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // 一个动画周期内走 3 个来回，速度接近真人声/音乐的起伏。
    final double t = animation.value * 2 * math.pi * 3;
    final double slot = size.width / _barCount;
    final double barWidth = slot * 0.62;
    final Radius radius = Radius.circular(barWidth / 2);
    final Paint paint = Paint()..color = color;
    for (int i = 0; i < _barCount; i++) {
      // 三条频率不同、相位按序号错开的正弦叠加：形成此起彼伏、不重复的跳动。
      final double phase = i * 0.9;
      final double wave =
          0.5 * math.sin(t + phase) + 0.3 * math.sin(t * 1.7 + phase * 1.6) + 0.2 * math.sin(t * 3.1 + phase * 0.7);
      final double ratio = _minRatio + (1 - _minRatio) * ((wave + 1) / 2);
      final double barHeight = size.height * ratio;
      final double left = i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight), radius),
        paint,
      );
    }
  }

  /// 逐帧重绘由 `super(repaint: animation)` 驱动，这里只比较静态属性。
  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter oldDelegate) => oldDelegate.color != color;
}

/// 时钟：`HH:mm:ss` + `年月日 农历 星期`，每秒刷新。
///
/// 时刻做成独立 StatefulWidget：定时刷新只重建这一小块，避免每秒
/// `setState` 波及上层 Stack 里的 [Video]，造成播放器反复重建。
class _ClockPanel extends StatefulWidget {
  const _ClockPanel({required this.color, this.timeSize = 32, this.horizontalSize = false});

  final Color color;

  /// 时间的字号；下方日期/农历按比例缩放。
  /// 左下角提示条用小号，音频整屏用大号。
  final double timeSize;

  final bool horizontalSize;

  @override
  State<_ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends State<_ClockPanel> {
  static final DateFormat _timeFmt = DateFormat('HH:mm:ss', 'zh_CN');
  static final DateFormat _dateFmt = DateFormat('y年M月d日', 'zh_CN');
  static final DateFormat _weekdayFmt = DateFormat('EEEE', 'zh_CN');

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 农历按月日换算；超出农历表范围（1900~2099）时降级为只显示公历。
    final LunarDate? lunar = lunarDateOf(DateTime(_now.year, _now.month, _now.day));
    final String subtitle = <String>[_dateFmt.format(_now)].join(' ');
    final String dateInChina = <String>[if (lunar != null) lunar.fullCnString, _weekdayFmt.format(_now)].join(' ');
    // 副行字号跟随主时间缩放（提示条里 timeSize=32 → 14，与原来一致）。
    final double subSize = (widget.timeSize * 0.44).clamp(14.0, 28.0);
    if (widget.horizontalSize) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _timeFmt.format(_now),
            style: TextStyle(
              color: widget.color,
              fontSize: widget.timeSize,
              height: 1.1,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: 32),
          Text(
            subtitle,
            style: TextStyle(color: widget.color, fontSize: subSize),
          ),
          SizedBox(width: 32),
          Text(
            dateInChina,
            style: TextStyle(color: widget.color, fontSize: subSize),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          _timeFmt.format(_now),
          style: TextStyle(
            color: widget.color,
            fontSize: widget.timeSize,
            height: 1.1,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(color: widget.color, fontSize: subSize),
        ),
        Text(
          dateInChina,
          style: TextStyle(color: widget.color, fontSize: subSize),
        ),
      ],
    );
  }
}

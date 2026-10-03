import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
import 'package:potatokid_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:potatokid_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:potatokid_screen/features/iptv/application/channel_source_cache.dart';
import 'package:potatokid_screen/features/iptv/application/home_now_playing_controller.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/remote/proxy_pool_service.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/channel_bar.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/direction_widget.dart';
import 'package:potatokid_screen/features/time/domain/lunar_calendar.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_days_panel.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_now_panel.dart';

/// 当前源的媒体类型（**只在运行时按真实轨道判定**，不看地址/名称）：
/// - [unknown]：刚打开，尚未判定，一律按**视频**的严格标准要求（默认视频）；
/// - [video]：确认存在真实视频轨（或已出画面）；
/// - [audio]：确认无视频轨，只有音频（广播台），看门狗改用宽松标准。
enum _MediaKind { unknown, video, audio }

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

  /// 当前频道正使用的源序号（同频道多源，失败时递增回退）。
  int _currentSource = 0;
  bool _handleFailureBusy = false;
  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本轮已试过的源序号：集齐该频道所有源即「一轮失败」，需要退避后再进下一轮。
  final Set<int> _triedSourcesThisRound = <int>{};

  /// 连续失败到「一整轮都没打开」的轮数：决定回到第一个源之前等多久。
  int _failedRounds = 0;

  /// 一整轮（该频道所有源都试过）都打不开后，回到第一个源之前的基础等待。
  static const Duration _roundRetryBaseDelay = Duration(seconds: 1);

  /// 退避的翻倍上限：1s → 2s → 4s → 8s。设为 0 即固定 1 秒不翻倍。
  static const int _maxRoundRetryShift = 3;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  /// 打开某源后若迟迟未进入播放的超时看门狗（解决“连了很久没反应”）。
  Timer? _hangWatchdog;
  static const Duration _hangTimeout = Duration(seconds: 60);

  /// 代理重试时的对应超时：免费代理普遍慢/不通，缩短以便尽快换下一个。
  static const Duration _proxyHangTimeout = Duration(seconds: 20);

  /// 当前生效的看门狗超时（代理模式更短）。
  Duration get _hangTimeoutNow => _proxyUrl == null ? _hangTimeout : _proxyHangTimeout;

  /// 进入播放即取消看门狗。
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _widthSub;

  /// 黑屏判定：是否出现过真实视频帧（width>0）。
  bool _playedVideo = false;

  /// 当前源的媒体类型判定结果。默认 [_MediaKind.unknown] → 按视频（严格）处理。
  ///
  /// 注意：**界面显示**不只看它是否为 audio —— [unknown]（还在连接）也显示音频界面，
  /// 见下方 `_AudioNowPlaying` 的 `visible`；它只决定「声条跳不跳」和看门狗标准。
  _MediaKind _mediaKind = _MediaKind.unknown;

  /// 声条是否跳动（只由 [_syncBarsActive] 更新）。
  ///
  /// 用 ValueNotifier 而不是 setState：播放状态变化很频繁，setState 会把上层
  /// [Video] 一起重建，切台时画面会闪。
  final ValueNotifier<bool> _barsActiveVN = ValueNotifier<bool>(false);

  /// 是否已收到过「真实视频轨」（排除 `auto`/`no` 以及封面图 albumart）。
  bool _hasVideoTrack = false;

  /// 当前源是否已上报过「播放成功」（音频源靠看门狗确认时去重）。
  bool _kindSuccessRecorded = false;

  /// 媒体类型判定的**兜底**计时器。
  ///
  /// 正常路径由轨道表立刻定论（见 `_tracksSub`），这个计时器只在
  /// 「轨道表一直没给出可用结论」时兜一下，避免 [unknown] 永远悬着 ——
  /// 那会让看门狗到期后无法结算，坏源就卡在黑屏上不切走了。
  Timer? _kindProbeTimer;

  /// 兜底判定窗口：这么久了轨道表还没结论，就按音频处理（宽松标准）。
  static const Duration _kindProbeTimeout = Duration(seconds: 8);
  static const Duration _proxyKindProbeTimeout = Duration(seconds: 8);

  /// 等待判定时挂起的完成回调（供「看门狗到期」时按最终判定处理）。
  VoidCallback? _pendingKindResolve;

  /// 轨道 / 音频参数订阅（用于运行时区分音频与视频节目）。
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<AudioParams>? _audioParamsSub;

  /// 音频输出参数是否已就绪（音频节目「已出声音」的证据）。
  bool _audioParamsReady = false;

  /// 当前生效的判定窗口。
  Duration get _kindProbeTimeoutNow => _proxyUrl == null ? _kindProbeTimeout : _proxyKindProbeTimeout;

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
      if (value) {
        // 真的开始播放了：本轮退避清零，下次再坏重新从 1 秒起算。
        _resetRound();
        _rememberCurrentSource();
      }
      // 音频节目的「已出声」证据之一；判定挂起时据此立即结算看门狗。
      _resolveMediaKindIfDecided();
      // 真的进入播放了 → 声条可以开始跳。
      _syncBarsActive();
    });
    // 出过视频帧（width>0）→ 视为有画面，取消黑屏看门狗。
    _widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0) {
        _playedVideo = true;
        // 有画面即确认是视频节目（音频判定到此推翻，居中的音频封面随之淡出）。
        _applyMediaKind(_MediaKind.video);
        _kindProbeTimer?.cancel();
        _hangWatchdog?.cancel();
        // 出画面说明该频道可用：本轮「清理失效源」的连续失败计数清零。
        final IptvChannel? channel = _currentChannel();
        if (channel != null) {
          ChannelFailureGuard.instance.recordSuccess(channel.name);
        }
      }
    });
    // 运行时区分「音频节目 / 视频节目」：只看真实轨道，不看地址与名称。
    // mpv 的 tracks 恒含 `auto`/`no` 两条伪轨，必须排除；
    // 纯音频文件常带封面图（albumart/image），这类也不算视频轨。
    //
    // 这里是**主要的判定入口**：轨道表在打开的瞬间就是完整的，
    // 「有音频轨、没有视频轨」即可立刻断定是音频台，不用再干等判定窗口。
    _tracksSub = player.stream.tracks.listen((Tracks tracks) {
      final bool hasRealVideo = tracks.video.any((VideoTrack t) {
        if (t.id == 'auto' || t.id == 'no') return false;
        return !(t.image ?? false) && !(t.albumart ?? false);
      });
      if (hasRealVideo) {
        _hasVideoTrack = true;
        if (_mediaKind != _MediaKind.video) {
          _applyMediaKind(_MediaKind.video);
          Injection.get<LogService>().info(
            '[LivePlayerWidget] 媒体类型判定:视频节目(有真实视频轨) '
            '频道${_currentChannel()?.name ?? '?'}源(${_currentSource + 1})',
          );
        }
        _kindProbeTimer?.cancel();
        _resolveMediaKindIfDecided();
        return;
      }
      // 没有视频轨，但有真实音频轨 → 音频节目，立即下结论。
      //
      // 要求「得有音频轨」是为了排掉刚 open 时那张空轨道表：
      // 若拿空表当依据，视频源会被误判成音频、闪一下广播界面。
      final bool hasRealAudio = tracks.audio.any((AudioTrack t) => t.id != 'auto' && t.id != 'no');
      if (hasRealAudio && _mediaKind != _MediaKind.audio) {
        _applyMediaKind(_MediaKind.audio);
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 媒体类型判定:音频节目(无视频轨) '
          '频道${_currentChannel()?.name ?? '?'}源(${_currentSource + 1})',
        );
        // 结论已出，兜底窗口没用了。
        _kindProbeTimer?.cancel();
      }
      _resolveMediaKindIfDecided();
    });
    // 音频输出参数就绪 → 音频节目的「确实出声了」证据。
    _audioParamsSub = player.stream.audioParams.listen((AudioParams p) {
      if (p.channelCount != null || p.sampleRate != null || p.format != null) {
        _audioParamsReady = true;
        _resolveMediaKindIfDecided();
        // 音频输出参数就绪 → 确实在出声，声条开始跳。
        _syncBarsActive();
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
    final bool healthy = playing && advanced && (_mediaKind == _MediaKind.audio || hasFrame);
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
      _showChannelToast(_channelSourceLabel());
      _markChannelsActivity();
    }
  }

  Future<void> _openChannel(int index, {bool force = false}) async {
    if (index < 0 || index >= widget.channels.length) return;
    final bool changed = index != _currentIndex;
    if (!force && !changed) return;
    _currentIndex = index;
    _currentSource = 0;
    // 换台是全新一轮试源：退避从 1 秒重新起算。
    _resetRound();
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
    // 代理也需在 open 前设置（只影响之后打开的流）。
    await _applyProxySetting(_proxyUrl);
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _lastOpenAt = DateTime.now();
    _bufferingAccum = Duration.zero; // 新源从零开始累计缓冲
    // 换源后媒体类型重新判定：地址/名称都不作依据，只看新源的真实轨道。
    _resetMediaKindProbe();
    _startHangWatchdog();
    try {
      String source = channel.sources[idx];
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length}) $source'
        '${_proxyUrl == null ? '' : '（代理 $_proxyUrl）'}',
      );
      await _player?.open(Media(channel.sources[idx]));
    } catch (e) {
      Injection.get<LogService>().error(
        '[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length}) 失败: $e',
      );
    }
  }

  /// 更新媒体类型判定结果并刷新界面（音频界面要显示/淡出收音机层）。
  ///
  /// 必须在轨道/判定回调里 setState：这些回调不经过 build，
  /// 不 setState 的话音频界面要等到别的重建时机才出现。
  void _applyMediaKind(_MediaKind kind) {
    if (_mediaKind != kind) {
      _mediaKind = kind;
      if (mounted) setState(() {});
    }
    // 类型没变时也可能要更新声条（例如换源后重置回 unknown、或音频参数就绪）。
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
    final bool active = _mediaKind == _MediaKind.audio && outputReady;
    if (_barsActiveVN.value != active) _barsActiveVN.value = active;
  }

  /// 换源/换台后重置媒体类型判定，并挂上兜底计时器。
  ///
  /// 默认回到 [_MediaKind.unknown]（按视频的严格标准要求）：只有拿到确凿证据
  /// （真实视频轨 / 真实音频轨 / 已出画面）才改变结论。
  /// 重置同时会淡出音频封面（新源可能是视频，不能让收音机图标压在画面上）；
  /// 声条也一并停掉，等新源真正出声的信号到了再跳。
  void _resetMediaKindProbe() {
    _kindProbeTimer?.cancel();
    _hasVideoTrack = false;
    _audioParamsReady = false;
    _kindSuccessRecorded = false;
    _pendingKindResolve = null;
    _applyMediaKind(_MediaKind.unknown);
    // 直接关掉声条：此刻 _player.state.playing 很可能还是**上一个源**的值
    // （新源正在连接），靠 _syncBarsActive 的判据会误判成「已经在播」。
    _barsActiveVN.value = false;
    _kindProbeTimer = Timer(_kindProbeTimeoutNow, _onKindProbeTimeout);
  }

  /// 兜底判定：这么久了轨道表仍未给出结论，就按音频处理（宽松标准）。
  ///
  /// 正常情况走不到这里 —— 音频台在轨道表一到就判成音频了。
  /// 兜底是为了让看门狗到期能结算：坏源（既没轨道也没出声）据此走
  /// `_onPlaybackIssue` 回退下一个源，而不是一直卡在黑屏。
  void _onKindProbeTimeout() {
    if (!mounted) return;
    if (_mediaKind != _MediaKind.unknown) return;
    if (_hasVideoTrack || _playedVideo) return;
    _applyMediaKind(_MediaKind.audio);
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 媒体类型判定:音频节目(无视频轨) 频道${_currentChannel()?.name ?? '?'}'
      '源(${_currentSource + 1})',
    );
    _resolveMediaKindIfDecided();
  }

  /// 判定已落定（音频且已出声 / 已确认视频）时，结算挂起的完成回调。
  ///
  /// 音频节目「确实在播」的证据是**已进入播放状态或音频输出参数就绪**，
  /// 不能用 width>0（纯音频永远没有视频帧）。
  void _resolveMediaKindIfDecided() {
    if (_pendingKindResolve == null) return;
    final bool decided =
        _mediaKind == _MediaKind.video ||
        (_mediaKind == _MediaKind.audio && (_audioParamsReady || _player?.state.playing == true));
    if (!decided) return;
    final VoidCallback? done = _pendingKindResolve;
    _pendingKindResolve = null;
    done?.call();
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

  /// 左下角频道名提示文案：`频道名称\n(源 i/N)`,如果要分割，可以用\n来切分。
  String _channelSourceLabel() {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return '';
    final int i = (_currentSource + 1).clamp(1, channel.sources.length);
    return '${channel.name}\n源 $i/${channel.sources.length}';
  }

  /// 左下角提示文案（按**选中**频道算），供选中瞬间立即回显频道名。
  ///
  /// 此刻还没提交播放、源号未知，先按首源显示；提交后 `_openChannel` 会用
  /// [_channelSourceLabel] 按真实源号再刷一次。
  String _selectedChannelLabel() {
    final int index = _channelController.index;
    if (index < 0 || index >= widget.channels.length) return '';
    final IptvChannel channel = widget.channels[index];
    if (channel.sources.isEmpty) return channel.name;
    return '${channel.name}\n源 1/${channel.sources.length}';
  }

  /// 启动“打开后长时间无画面”看门狗。
  ///
  /// 打开源后 [_hangTimeout]（直连 60 秒 / 代理 20 秒）内若既未开始播放、
  /// 或一直没出现视频帧（黑屏），则回退下一个源。出现视频帧(width>0)即取消。
  /// 特别注意：黑屏时 stream 的 position 仍可能推进，故**不用 position 作健康信号**。
  ///
  /// **音频节目分流**：判定为音频的源（广播台）本就没有视频帧，只要求
  /// 「已进入播放或已出声」，不做「必须有视频帧」的断言；判定未定时
  /// 先按视频严格处理（默认视频），判定窗口到期后自动改写类型再结算。
  void _startHangWatchdog() {
    // 重置健康信号，等待视频帧。
    _playedVideo = false;
    _hangWatchdog?.cancel();
    final Duration timeout = _hangTimeoutNow;
    _hangWatchdog = Timer(timeout, () {
      if (!mounted) return;
      // 已在使用其它源则忽略。
      if (_player?.state.playlist.index != _currentSource) return;
      final bool playing = _player?.state.playing ?? false;
      final String name = _currentChannel()?.name ?? '?';
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 看门狗到期 频道$name源(${_currentSource + 1}) '
        '媒体类型=${_mediaKind.name} playing=$playing '
        'buffering=${_player?.state.buffering} width=${_player?.state.width}',
      );
      if (_mediaKind == _MediaKind.unknown) {
        // 判定还没落定：先按最终判定收尾（换源立即结算；音频等出声后结算）。
        _pendingKindResolve = _finishHangWatchdog;
        _resolveMediaKindIfDecided();
        return;
      }
      _finishHangWatchdog();
    });
  }

  /// 看门狗到期的实际结算（按已确定的媒体类型给不同标准）。
  void _finishHangWatchdog() {
    if (!mounted) return;
    final bool playing = _player?.state.playing ?? false;
    final int timeoutSec = _hangTimeoutNow.inSeconds;
    if (_mediaKind == _MediaKind.audio) {
      // 音频节目：确有音频输出（播放状态 / 已解码出音频参数）即视为成功。
      final bool audioAlive = playing || _audioParamsReady;
      if (audioAlive) {
        final IptvChannel? channel = _currentChannel();
        if (channel != null && !_kindSuccessRecorded) {
          _kindSuccessRecorded = true;
          ChannelFailureGuard.instance.recordSuccess(channel.name);
        }
        return;
      }
      _onPlaybackIssue(reason: '音频源打开${timeoutSec}s后仍无音频输出');
      return;
    }
    if (!playing) {
      _onPlaybackIssue(reason: '打开${timeoutSec}s后未进入播放');
    } else if (!_playedVideo) {
      _onPlaybackIssue(reason: '打开${timeoutSec}s后无视频帧(黑屏)');
    }
  }

  /// 左/右键手动切换当前频道的源（循环换向）。
  void _switchSource(int delta) {
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    final int n = channel.sources.length;
    _currentSource = (_currentSource + delta + n) % n;
    // 手动换源是用户主动重试：本轮退避清零。
    _resetRound();
    Injection.get<LogService>().info('[LivePlayerWidget] 手动切换频道:${channel.name},源(${_currentSource + 1}/$n)');
    _playCurrentSource();
    // 刷新提示并保持可见，便于连续左右切源。
    if (mounted) _showChannelToast(_channelSourceLabel());
  }

  /// 播放失败/结束：先用代理重试同一个源，再循环回退到下一个源。
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
    // 本次失败对应的源（自增回退前），供「清理失效源」统计失效地址。
    final int failedIndex = _currentSource.clamp(0, channel.sources.length - 1);
    final String failedUrl = channel.sources[failedIndex];

    // 「代理重试」第一段：这次失败发生在代理上 → 换下一个代理继续试同一个源。
    if (_proxyUrl != null) {
      Injection.get<LogService>().info('[LivePlayerWidget] 代理未成功，换下一个: $_proxyUrl，原因: $reason');
      _proxyUrl = null;
    }

    // 「代理重试」第二段：直连失败，或代理失败但还没试满 → 挑一个**探测可用**的代理
    // 重试**同一个源**（探测能挡住「代理能连上但对这个源返回错误页」这类无效代理）。
    if (AppSettings.instance.proxyRetryEnabled && _proxyAttempts < _maxProxyAttempts) {
      final String? proxy = await ProxyPoolService.instance.nextUsableProxy(targetUrl: failedUrl);
      // 等待探测期间可能已切台/切源，需复核。
      if (proxy != null && mounted && _currentChannel()?.name == channel.name) {
        _proxyAttempts++;
        _proxyUrl = proxy;
        _currentSource = failedIndex;
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 改用代理重试(第$_proxyAttempts次):${channel.name},'
          '源(${failedIndex + 1}/${channel.sources.length}) 代理=$proxy，原因: $reason',
        );
        await _playCurrentSource();
        _handleFailureBusy = false;
        _recordInvalidFailure(channel, failedUrl, reason);
        if (mounted) _showChannelToast(_channelSourceLabel());
        return;
      }
      Injection.get<LogService>().info('[LivePlayerWidget] 未找到可用代理（已尝试 $_proxyAttempts 次），回退下一个源');
    }

    // 代理都没救活（或未开启）→ 回退到下一个源，重新从直连开始。
    _proxyAttempts = 0;
    // 该频道所有源都各试过一次 = 一轮结束：回到第一个源之前先退避一会儿。
    // 否则「全源都打不开」时会以 mpv 报错的速度（实测 20~140ms）不停 open/失败，
    // 每个 open 都要重建解码器与 Surface，盒子会持续抖动、日志也会被刷爆。
    _triedSourcesThisRound.add(failedIndex);
    if (_triedSourcesThisRound.length >= channel.sources.length) {
      _triedSourcesThisRound.clear();
      _failedRounds++;
      final Duration wait = _roundRetryDelay();
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 频道${channel.name} 全部 ${channel.sources.length} 个源都打不开，'
        '第$_failedRounds轮，${wait.inMilliseconds}ms 后重试',
      );
      final int failedSource = _currentSource;
      await Future<void>.delayed(wait);
      // 等待期间可能已换台 / 手动换源 / 退出：过期就放弃这次回退，
      // 否则会把用户刚选好的源又顶掉。
      if (!mounted || _currentChannel()?.name != channel.name || _currentSource != failedSource) {
        _handleFailureBusy = false;
        return;
      }
    }
    _currentSource = (_currentSource + 1) % channel.sources.length;
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 切换频道:${channel.name},源'
      '(${_currentSource + 1}/${channel.sources.length})，原因: $reason',
    );
    await _playCurrentSource();
    _handleFailureBusy = false;
    _recordInvalidFailure(channel, failedUrl, reason);
    // 刷新左下角里的源序号提示。
    if (mounted) _showChannelToast(_channelSourceLabel());
  }

  /// 本轮退避时长：1s、2s、4s、8s（上限）。
  ///
  /// 坏台会一直重试，固定 1 秒虽然远好过空转，但长期看仍是每分钟 60 次 open；
  /// 递增后逐步降到每分钟 7~8 次，持续不可用时不至于拖累盒子。
  Duration _roundRetryDelay() {
    final int shift = (_failedRounds - 1).clamp(0, _maxRoundRetryShift);
    return Duration(milliseconds: _roundRetryBaseDelay.inMilliseconds << shift);
  }

  /// 开始新的一轮试源（换台 / 手动换源 / 播放成功后调用）：退避重新从 1 秒起算。
  void _resetRound() {
    _triedSourcesThisRound.clear();
    _failedRounds = 0;
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
    _hangWatchdog?.cancel();
    _kindProbeTimer?.cancel();
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
            buildWhen: (previous, current) => previous.aspectMode != current.aspectMode,
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
          // 音频节目（广播台）没有画面，纯黑底上居中显示收音机图标 + 频道名。
          // 不可交互（IgnorePointer），不影响遥控器按键与频道条。
          Positioned.fill(
            child: IgnorePointer(
              child: _AudioNowPlaying(
                label: _channelSourceLabel(),
                // 只在下结论为音频时显示：[unknown]（还在连接/未判定）保持黑屏，
                // 结论由轨道表立刻给出（见 _tracksSub），不等判定窗口。
                visible: _mediaKind == _MediaKind.audio,
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
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ClockPanel(color: Colors.white, timeSize: timeSize),
                const SizedBox(height: 36),
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
                const SizedBox(height: 56),
                Transform.scale(
                  scale: 2.0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[WeatherNowPanel(), SizedBox(width: 24), WeatherDaysPanel()],
                  ),
                ),
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
  const _ClockPanel({required this.color, this.timeSize = 32});

  final Color color;

  /// 时间的字号；下方日期/农历按比例缩放。
  /// 左下角提示条用小号，音频整屏用大号。
  final double timeSize;

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

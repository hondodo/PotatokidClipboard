import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/app_exit_controller.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:pscreen_screen/core/media/video_aspect_mode.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/features/iptv/application/buffer_stall_watchdog.dart';
import 'package:pscreen_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_source_cache.dart';
import 'package:pscreen_screen/features/iptv/application/home_now_playing_controller.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';
import 'package:pscreen_screen/features/iptv/application/playback_retry_controller.dart';
import 'package:pscreen_screen/features/iptv/application/playback_watchdog.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';
import 'package:pscreen_screen/features/iptv/application/relay_policy.dart';
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

class _LivePlayerWidgetState extends State<LivePlayerWidget>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _controller;
  final LiveChannelController _channelController =
      LiveChannelController.instance;
  Timer? _toastTimer;

  /// 左下角频道名提示（ValueNotifier 避免 setState 导致整棵树重建而闪烁）
  final ValueNotifier<String?> _toastNameVN = ValueNotifier<String?>(null);
  int _currentIndex = 0;

  /// 打开频道请求的序号（见 `_openChannel`）：用于丢弃 await 期间已过期的打开请求。
  int _openSeq = 0;

  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 播放失败重试状态机（共享包 `PlaybackRetryController`）：700ms 冷却、
  /// 多源循环回退、一轮判定与 1→2→4→8s 退避都在它内部；失败现场上报经
  /// `onEnterRetry` 注入。
  late final PlaybackRetryController _retry;

  /// 媒体类型判定（共享包 `MediaKindProbe`）：只看真实轨道区分音频台/视频台，
  /// 结论与证据（[_playedVideo] / [_audioParamsReady]）都读它。
  late final MediaKindProbe _probe;

  /// 「打开后长时间无画面」看门狗（共享包 `PlaybackWatchdog`）：
  /// 超时取 [_hangTimeout]，到期按媒体类型分流结算，
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

  /// 是否已应用 Android 音频输出后端（全局选项，只需在首次 open 前设一次）。
  bool _audioOutputApplied = false;

  /// 进入播放即推进看门狗结算。
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _widthSub;

  /// 卡顿事件记账（buffering 边沿）：playing 期间 buffering=true 记起点，
  /// 恢复时超过 1s 打一条日志——用于与 relay 侧的请求空窗对表。
  StreamSubscription<bool>? _bufferingSub;
  DateTime? _stallStart;

  /// 当前源是否已打过分「起播确认」日志（每次 open 清空）。
  /// 现场只有 release 包，靠它确认「看门狗计时」到底从第几秒开始算。
  bool _establishedLogged = false;

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

  /// 「持续缓冲卡死」两级看门狗（共享包 `BufferStallWatchdog`）：
  /// 一级 10s 原地重载同源（吸收 relay 会话重建空窗）、二级 60s 换源；
  /// 只有真正起播后才计时，稳定播放 5s 才补满重载额度（启动期不算卡死）。
  late final BufferStallWatchdog _bufferStall;
  Timer? _bufferStallWatch;

  /// 最近一次记住的「频道|源URL」，避免重复写盘。
  String? _lastRemembered;

  /// 频道列表「10 秒无操作」自动收起的计时器。
  Timer? _channelsHideTimer;
  static const Duration _channelsHideDelay = Duration(seconds: 5);

  /// 换台时临时「预览」频道列表：遥控上/下换台只走 channelInfo 层，
  /// 不进入 channelList（那会接管方向键、破坏换台），所以列表显隐要
  /// 独立于交互层——这里只负责显示，不可聚焦、不可触控。
  bool _listPeek = false;
  Timer? _listPeekTimer;

  /// 硬解设置已应用到播放器的 Future（_playCurrentSource 会等待它，
  /// 确保进入播放前 hwdec 属性已正确设置）。
  Future<void>? _hwdecReady;

  /// 儿童模式锁屏暂停：锁屏出现即暂停直播，解锁后恢复；锁屏期间即使开启
  /// 「后台播放」也在退到后台时暂停（[KidWatchTimerController.locked] 为准）。
  bool _lockedPaused = false;
  bool _lastKidLocked = false;
  bool _appInBackground = false;

  /// 退出清理开始后禁止所有延迟任务、失败回退和生命周期回调重新开流。
  bool _appExiting = false;

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
    // ---- 共享包四件套（媒体判定 / 看门狗 / 重试状态机 / 缓冲卡死看门狗），先建再挂订阅 ----
    _probe = MediaKindProbe(onChanged: _onProbeChanged);
    _watchdog = PlaybackWatchdog(
      probe: _probe,
      isPlaying: () => _player?.state.playing ?? false,
      onIssue: (String reason) => _onPlaybackIssue(reason: reason),
      timeoutOf: () => _hangTimeout,
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
        if (channel != null) {
          ChannelFailureGuard.instance.recordSuccess(channel.name);
        }
      },
    );
    // 两级「持续缓冲」看门狗：一级原地重载同源，二级才换源进重试。
    _bufferStall = BufferStallWatchdog(
      onReload: (int attempt) {
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 一级看门狗 原地重载 频道${_currentChannel()?.name ?? '?'}'
          '源(${_currentSource + 1}) 缓冲10s+ (第$attempt/${_bufferStall.reloadMax} 次) '
          '距open=${DateTime.now().difference(_lastOpenAt).inSeconds}s '
          'width=${_player?.state.width} playedVideo=${_probe.playedVideo} '
          'audioParams=${_probe.audioParamsReady}',
        );
        unawaited(_playCurrentSource(isReload: true));
      },
      onStuck: (Duration accum) {
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 看门狗 持续缓冲卡死 频道${_currentChannel()?.name ?? '?'}'
          '源(${_currentSource + 1}) 累计${accum.inSeconds}s '
          'width=${_player?.state.width}',
        );
        _onPlaybackIssue(reason: '持续缓冲卡死(${accum.inSeconds}s)');
      },
    );
    _retry = PlaybackRetryController(
      sourceCount: () => _currentChannel()?.sources.length ?? 0,
      open: (int sourceIndex) => _playCurrentSource(),
      // 失败现场（必须在换源之前）：上报 play_retry + 统计失效源。
      onEnterRetry: (String reason) {
        _reportPlayback('play_retry', reason: reason);
        _recordInvalidSourceFailure(reason);
      },
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
      if (trimmed.contains('Cannot seek in this stream') ||
          trimmed.contains('--force-seekable') ||
          trimmed.contains('Failed to recognize file format.')) {
        Injection.get<LogService>().info(
          '[LivePlayerWidget] 忽略非致命错误(不影响播放): $trimmed',
        );
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
      final String detail = trimmed.length > 120
          ? '${trimmed.substring(0, 120)}…'
          : trimmed;
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
    // 卡顿事件记账（毫秒级边沿）：playing 期间进入 buffering 即记起点，
    // 恢复时超过 1s 打一条「卡顿 X.Xs 后恢复」——与 relay 侧请求空窗对表。
    _bufferingSub = player.stream.buffering.listen((bool b) {
      if (!mounted) return;
      if (b) {
        // 门控：只记「已经在播」的卡，首次 open 的 buffering 是正常起播。
        if (_player?.state.playing == true) _stallStart ??= DateTime.now();
      } else if (_stallStart != null) {
        final int ms = DateTime.now().difference(_stallStart!).inMilliseconds;
        _stallStart = null;
        if (ms >= 1000) {
          Injection.get<LogService>().info(
            '[LivePlayerWidget] 卡顿 ${(ms / 1000).toStringAsFixed(1)}s 后恢复 '
            '源(${_currentSource + 1}) width=${_player?.state.width}',
          );
        }
      }
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
    _bufferStallWatch = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkBufferStall(),
    );
    // 同步频道数与当前选中频道，随后监听上/下键的切换。
    _syncChannels();
    // 「选中」立即刷新界面，「播放提交」延迟换源（两者分开的原因见控制器注释）。
    _channelController.addListener(_onChannelSelected);
    _channelController.onPlayCommit.addListener(_onPlayCommit);
    HomeNowPlayingController.instance.onSwitchSource = _switchSource;
    HomeNowPlayingController.instance.onShowChannelInfo =
        _showCurrentChannelInfo;
    HomeNowPlayingController.instance.onShowChannelPanel = _showChannelPanel;
    HomeNowPlayingController.instance.onHideChannelPanel = _hideChannelPanel;
    AppExitController.instance.attachPlaybackCleanup(_stopForAppExit);
    // 锁屏/解锁边沿：锁屏即暂停、解锁即恢复（儿童模式）。
    _lastKidLocked = KidWatchTimerController.instance.locked;
    KidWatchTimerController.instance.addListener(_onKidLockChanged);
    if (_lastKidLocked) _pauseForLock();
    _restoreLastChannel();
  }

  /// 儿童模式锁屏状态变化：锁定 → 暂停；解除 → 恢复（后台时先不恢复，
  /// 回前台再恢复，避免后台出声）。
  void _onKidLockChanged() {
    if (_appExiting) return;
    final bool locked = KidWatchTimerController.instance.locked;
    if (locked == _lastKidLocked) return;
    _lastKidLocked = locked;
    if (locked) {
      _pauseForLock();
    } else {
      _resumeFromLock();
    }
  }

  void _pauseForLock() {
    final Player? p = _player;
    if (p == null) return;
    if (p.state.playing) {
      _lockedPaused = true;
      unawaited(p.pause());
    }
  }

  void _resumeFromLock() {
    if (_appExiting) return;
    if (!_lockedPaused) return;
    // 仍锁定或仍在后台：保持暂停，等回前台/解锁后再恢复（不能先清标记）。
    if (KidWatchTimerController.instance.locked || _appInBackground) return;
    _lockedPaused = false;
    unawaited(_player?.play());
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
    // 频道名立即跟着选中走（此时源序号按首源显示，提交后会用真实源号再刷一次）。
    if (!mounted) return;
    final bool inControls =
        context.read<AppBloc>().state.homeRemoteLayer ==
        HomeRemoteLayer.channelList;
    _showChannelToast(_selectedChannelLabel(), enterInfoLayer: !inControls);
    if (inControls) {
      _armChannelsHide();
    } else {
      // 全屏换台：顺带把频道列表「预览」出来（不可聚焦/触控，5 秒后自动收起）。
      // 遥控逻辑保持不变：上/下换台、左/右切源、OK 才进入可操作的列表。
      _peekChannelList();
    }
  }

  /// 播放提交（停止切换 `LiveChannelController.commitDelay` 后）：真正换源。
  void _onPlayCommit() {
    if (_appExiting) return;
    _openChannel(_channelController.index);
    // 记录当前频道，下次启动据此恢复（写盘也一并挪到这里，避免长按时反复写）。
    _rememberCurrentChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_appExiting) return;
    if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      // 锁屏仍然成立：保持暂停，不做恢复健康检测（否则会主动重开流）。
      if (KidWatchTimerController.instance.locked) {
        _pauseForLock();
        return;
      }
      _resumeFromLock();
      // 返回前台不再无条件重开：先做短时健康检测，只有确认播放已损坏才重开，
      // 避免「短暂离开后回来其实还能正常播」也被强制重新加载（闪黑、重新缓冲）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkResumeHealth();
      });
      return;
    }
    _appInBackground = true;
    // 儿童模式锁屏期间：即使开了「后台播放」也不允许后台继续出声。
    if (KidWatchTimerController.instance.locked) _pauseForLock();
  }

  /// 恢复前台后的播放健康检测（解决 RN/媒体 Surface 被销毁的固有风险）。
  ///
  /// 给播放器一点时间重建 Surface / 恢复解码，随后综合判断：
  /// - [playing] 为 true、且 position 相对「回前台起点」持续推进 → 健康，不打扰；
  /// - 视频节目还要求出现过视频帧（width>0）；音频节目（广播台）本就没有视频帧，
  ///   不能用它判健康，否则每次回前台都会无谓重载；
  /// - 否则判定损坏（Surface 可能已销毁 / 解码停滞），对当前源重新 play。
  Future<void> _checkResumeHealth() async {
    if (_appExiting) return;
    final Player? p = _player;
    if (p == null) return;
    final Duration resumePos = p.state.position;
    // 重建 Surface / 恢复解码的缓冲时间。正常播放时 1.5s 内 position 会持续推进。
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || _appExiting || _player != p) return;
    final dynamic s = p.state;
    final bool playing = s.playing;
    final bool hasFrame = (s.width ?? 0) > 0;
    final bool advanced =
        (s.position - resumePos) >= const Duration(milliseconds: 500);
    // 只有「判定为音频」才放宽视频帧要求；unknown 仍按视频严格处理（默认视频）。
    final bool healthy =
        playing && advanced && (_mediaKind == MediaKind.audio || hasFrame);
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
    if (_appExiting) return;
    // 默认首台(0)。
    int target = _channelController.index;
    final String? last = await ChannelSourceCache.instance.lastChannelName();
    if (_appExiting) return;
    if (last != null) {
      final int idx = widget.channels.indexWhere(
        (IptvChannel c) => c.name == last,
      );
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
    context.read<AppBloc>().add(
      const SetHomeRemoteLayer(HomeRemoteLayer.channelList),
    );
    _armChannelsHide();
  }

  void _armChannelsHide() {
    _channelsHideTimer?.cancel();
    _channelsHideTimer = Timer(_channelsHideDelay, () {
      _channelsHideTimer = null;
      if (!mounted) return;
      _toastTimer?.cancel();
      _toastNameVN.value = null;
      context.read<AppBloc>().add(
        const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
      );
    });
  }

  void _showCurrentChannelInfo() {
    if (!mounted) return;
    _showChannelToast(
      _channelSourceLabel(withNumber: true),
      enterInfoLayer: true,
    );
  }

  /// 全屏换台时短暂展示频道列表（只显示、不接管按键），5 秒后自动收起。
  void _peekChannelList() {
    if (!mounted) return;
    if (!_listPeek) setState(() => _listPeek = true);
    _listPeekTimer?.cancel();
    _listPeekTimer = Timer(_channelsHideDelay, () {
      _listPeekTimer = null;
      if (!mounted) return;
      setState(() => _listPeek = false);
    });
  }

  void _clearChannelPeek() {
    _listPeekTimer?.cancel();
    _listPeekTimer = null;
    if (_listPeek) setState(() => _listPeek = false);
  }

  void _showChannelPanel() {
    if (!mounted) return;
    // 正式面板接管后清除预览态，避免关闭面板时预览列表继续残留。
    _clearChannelPeek();
    _showChannelToast(
      _channelSourceLabel(withNumber: true),
      enterInfoLayer: false,
    );
    _markChannelsActivity();
  }

  void _hideChannelPanel() {
    if (!mounted) return;
    _clearChannelPeek();
    _toastTimer?.cancel();
    _toastNameVN.value = null;
    _channelsHideTimer?.cancel();
    _channelsHideTimer = null;
    context.read<AppBloc>().add(
      const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
    );
  }

  void _activateChannelFromPanel(int index) {
    _channelController.select(index);
    _hideChannelPanel();
  }

  Future<void> _openChannel(int index, {bool force = false}) async {
    if (_appExiting) return;
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
    // 优先从上次可用源起播（记忆的 URL 已不在此频道则回落首源）。
    final String? preferred = await ChannelSourceCache.instance
        .preferredSourceOf(widget.channels[index].name);
    if (!mounted || _appExiting || seq != _openSeq) return;
    if (preferred != null) {
      final int idx = widget.channels[index].sources.indexOf(preferred);
      if (idx >= 0) _retry.sourceIndex = idx;
    }
    if (mounted) setState(() {});
    if (changed || force) {
      // 切台时抑制旧流的 error/completing 干扰。
      _retry.setBusy(true);
      await _playCurrentSource();
      if (_appExiting) return;
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

  /// 每秒把播放状态喂给共享的两级看门狗 [_bufferStall]（一级 10s 原地重载 /
  /// 二级 60s 换源）：只有**真正起播后**（出过帧 / 音频参数就绪）才累计计时，
  /// 启动拉流阶段不计时，避免慢站刚出声就被重载掐断。
  void _checkBufferStall() {
    if (!mounted) return;
    final dynamic s = _player?.state;
    if (s == null) return;
    final bool established = _probe.playedVideo || _probe.audioParamsReady;
    // 起播确认打一次点：看门狗从此刻才开始累计缓冲时长。
    if (established && !_establishedLogged) {
      _establishedLogged = true;
      Injection.get<LogService>().info(
        '[LivePlayerWidget] 起播确认 频道${_currentChannel()?.name ?? '?'}'
        '源(${_currentSource + 1}) 距open=${DateTime.now().difference(_lastOpenAt).inSeconds}s '
        'width=${s.width} playedVideo=${_probe.playedVideo} '
        'audioParams=${_probe.audioParamsReady}',
      );
    }
    _bufferStall.notifyState(
      playing: s.playing,
      buffering: s.buffering,
      established: established,
    );
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
    await (player.platform as NativePlayer).setProperty(
      'hwdec',
      enabled ? 'auto' : 'no',
    );
    // media_kit 默认把 mpv 的 network-timeout 设为 5s：弱网 / 慢 CDN（珠江台的
    // 播放列表常要 10s+）会在起播前就被 ffurl_read ETIMEDOUT 掐断，表现成
    // 「一直打不开、每隔十来秒重试」。放宽到 30s；真正的坏源仍由打开看门狗兜底。
    await (player.platform as NativePlayer).setProperty(
      'network-timeout',
      '30',
    );
  }

  /// 切换 Android 音频输出后端（仅 Android，且只在首次 open 前设一次）。
  ///
  /// media_kit 在 Android 默认用 OpenSL ES（`ao=opensles`），部分设备上对
  /// URL 直播源的输出电平偏低 / 音质偏差；改走 AudioTrack（`ao=audiotrack`）
  /// 可直接改善这一现象。写成 `audiotrack,opensles` 的驱动列表：audiotrack
  /// 在个别设备上初始化失败时 mpv 会自动回退到 opensles，不会变成无声。
  Future<void> _applyAudioOutput() async {
    if (_audioOutputApplied) return;
    _audioOutputApplied = true;
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return;
      if (_player?.platform is! NativePlayer) return;
      await (_player?.platform as NativePlayer).setProperty(
        'ao',
        'audiotrack,opensles',
      );
    } catch (_) {
      // 设置失败不阻断播放（回落 media_kit 默认的 opensles）。
    }
  }

  /// 是否为「音轨解码失败」类错误（画面可能完全正常）。
  static bool _isAudioDecodeError(String msg) =>
      msg.contains('Error decoding audio') ||
      msg.contains('Failed to decode audio');

  /// 画面是否已经健康：出过真实视频帧、已判定为「有视频轨的节目」、或已在播放。
  ///
  /// 只有这种情况下的音轨报错才值得忽略。连视频都没起来的源仍按原逻辑回退，
  /// 交给看门狗与回退机制处理，避免「音轨坏 = 整个源不可用」的误判反过来漏掉真坏源。
  bool _isPlaybackHealthy() =>
      _playedVideo ||
      _mediaKind == MediaKind.video ||
      (_player?.state.playing ?? false);

  /// 打开当前频道的当前源。
  ///
  /// [isReload] = 一级看门狗的原地重载：沿用同一源，**不清零**重载额度；
  /// 其余调用（切台/换源/重试）恢复满额。
  Future<void> _playCurrentSource({bool isReload = false}) async {
    if (_appExiting) return;
    final IptvChannel? channel = _currentChannel();
    if (channel == null || channel.sources.isEmpty) return;
    if (!isReload) _bufferStall.onFreshOpen();
    // 确保硬解设置已应用到播放器（mpv 的 hwdec 需在 open 前设置才生效）。
    await _hwdecReady;
    if (_appExiting) return;
    // Android 音频输出后端（ao=audiotrack）：只在首次 open 前设一次。
    await _applyAudioOutput();
    if (_appExiting) return;

    /// 直播真的很小声，只能调整到120，可能出现爆音；遥控的音量指的是改系统全局，不要将遥控的音量接入到这里修改
    _player?.setVolume(120);
    final int idx = _currentSource.clamp(0, channel.sources.length - 1);
    _lastOpenAt = DateTime.now();
    // 刷新重试状态机的 700ms 冷却基准。
    _retry.markOpen();
    // 每次 open 重新允许记录一次「忽略音频解码错误」。
    _audioDecodeErrorLogged = false;
    // 换源后媒体类型重新判定：地址/名称都不作依据，只看新源的真实轨道。
    _probe.reset();
    // 新源重新打「起播确认」点。
    _establishedLogged = false;
    // 开新流：丢弃上一条流未收尾的卡顿起点，避免跨 open 误记时长。
    _stallStart = null;
    // 此刻 playing 还是上一个源的值，声条直接停掉（新源真正出声再跳）。
    _barsActiveVN.value = false;
    _watchdog.arm();
    try {
      String source = channel.sources[idx];
      // 测试特定地址
      // source = 'http://r.jdshipin.com/CkuBd';

      // 云端 HLS 中转（`.env` 的 `REPLY_SOURCE`）：非空且源域名命中服务端
      // 下发的中转白名单（/api/allow_reply_host，见 RelayPolicy）时才改写为
      // 中转前缀 + urlencode(源地址)；未命中（或 relay 为空）则直连播放。
      final String relay = AppConfig.relaySource;
      if (relay.isNotEmpty && await RelayPolicy.instance.shouldRelay(source)) {
        if (_appExiting) return;
        source = '$relay${Uri.encodeComponent(source)}';
        // 附带稳定设备号（16 位 hex）：relay 据此识别「同一设备换源」并
        // 立即淘汰旧转码进程，不再等 60s 空闲回收。设备号不可用则省略。
        final String devId = await DeviceCredentials.deviceId();
        if (_appExiting) return;
        if (devId.isNotEmpty) source = '$source&dev=$devId';
      }

      Injection.get<LogService>().info(
        '[LivePlayerWidget] 播放频道:${channel.name},源(${idx + 1}/${channel.sources.length}) $source',
      );
      await _player?.open(Media(source));
      _reportPlayback('play_start');
      // 锁屏期间打开新流（启动恢复频道/切源）：开完立即暂停，避免出声。
      if (KidWatchTimerController.instance.locked) {
        _lockedPaused = true;
        await _player?.pause();
      }
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
    final bool outputReady =
        _audioParamsReady || (_player?.state.playing ?? false);
    final bool active = _mediaKind == MediaKind.audio && outputReady;
    if (_barsActiveVN.value != active) _barsActiveVN.value = active;
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
    Injection.get<LogService>().info(
      '[LivePlayerWidget] 手动切换频道:${channel.name},源(${_currentSource + 1}/$n)',
    );
    _playCurrentSource();
    // 刷新提示并保持可见，便于连续左右切源。
    if (mounted) _showChannelToast(_channelSourceLabel(withNumber: true));
  }

  /// 播放失败/结束/看门狗到期：交给共享重试状态机
  /// （冷却过滤 → 失败现场上报 → 一轮退避 → 循环换源，
  /// 见 [PlaybackRetryController]）。
  void _onPlaybackIssue({String reason = '', bool bypassCooldown = false}) {
    if (_appExiting) return;
    unawaited(
      _retry.handleIssue(reason: reason, bypassCooldown: bypassCooldown),
    );
  }

  /// 退出前先静音式暂停，再停止媒体管线；stop 会关闭直播连接并释放音频输出。
  Future<void> _stopForAppExit() async {
    if (_appExiting) return;
    _appExiting = true;
    _openSeq++;
    _retry.setBusy(true);
    _toastTimer?.cancel();
    _channelsHideTimer?.cancel();
    _listPeekTimer?.cancel();
    _bufferStallWatch?.cancel();
    _watchdog.cancel();
    _barsActiveVN.value = false;

    final Player? player = _player;
    if (player == null) return;
    try {
      // 先静音，避免部分 Android 音频后端在 pause/stop 释放期间残留声音。
      await player.setVolume(0);
    } catch (_) {
      // 静音失败仍继续暂停和停止。
    }
    try {
      await player.pause();
    } catch (_) {
      // 继续执行 stop，确保退出不被单个播放器调用阻断。
    }
    try {
      await player.stop();
    } catch (_) {
      // 平台随后会退出进程；此处失败不再恢复播放。
    }
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
  void _recordInvalidFailure(
    IptvChannel channel,
    String failedUrl,
    String reason,
  ) {
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
  void _showChannelToast(String name, {bool enterInfoLayer = true}) {
    _toastTimer?.cancel();
    _toastNameVN.value = name;
    if (enterInfoLayer) {
      final HomeRemoteLayer layer = context
          .read<AppBloc>()
          .state
          .homeRemoteLayer;
      if (layer == HomeRemoteLayer.fullscreen ||
          layer == HomeRemoteLayer.channelInfo) {
        context.read<AppBloc>().add(
          const SetHomeRemoteLayer(HomeRemoteLayer.channelInfo),
        );
      }
    }
    _toastTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _toastNameVN.value = null;
      if (context.read<AppBloc>().state.homeRemoteLayer ==
          HomeRemoteLayer.channelInfo) {
        context.read<AppBloc>().add(
          const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
        );
      }
    });
  }

  @override
  void dispose() {
    AppExitController.instance.detachPlaybackCleanup();
    WidgetsBinding.instance.removeObserver(this);
    KidWatchTimerController.instance.removeListener(_onKidLockChanged);
    _channelController.removeListener(_onChannelSelected);
    _channelController.onPlayCommit.removeListener(_onPlayCommit);
    HomeNowPlayingController.instance.onSwitchSource = null;
    HomeNowPlayingController.instance.onShowChannelInfo = null;
    HomeNowPlayingController.instance.onShowChannelPanel = null;
    HomeNowPlayingController.instance.onHideChannelPanel = null;
    _toastTimer?.cancel();
    _toastNameVN.dispose();
    _barsActiveVN.dispose();
    _channelsHideTimer?.cancel();
    _listPeekTimer?.cancel();
    _watchdog.dispose();
    _probe.dispose();
    _bufferStallWatch?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
    _widthSub?.cancel();
    _bufferingSub?.cancel();
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
          (p.platform as NativePlayer).setProperty(
            'hwdec',
            state.hwdecEnabled ? 'auto' : 'no',
          );
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
          // 右侧频道条；胶囊与页面 Tab 统一由 MainApp 的全局 Mask 承载。
          Align(
            alignment: Alignment.centerRight,
            child: BlocBuilder<AppBloc, AppState>(
              buildWhen: (previous, current) =>
                  previous.showChannels != current.showChannels ||
                  previous.homeRemoteLayer != current.homeRemoteLayer,
              builder: (context, state) {
                // interactive：OK 打开的「可操作」频道列表层。
                final bool interactive = state.showChannels;
                // visible：可操作列表，或换台时的临时预览（仅全屏/频道信息层）。
                final bool layerAllowsPeek =
                    state.homeRemoteLayer == HomeRemoteLayer.fullscreen ||
                    state.homeRemoteLayer == HomeRemoteLayer.channelInfo;
                final bool visible =
                    interactive || (_listPeek && layerAllowsPeek);
                // 列表处于可见时确保有 30 秒计时（初始显示也算）。
                if (interactive && (mounted && _channelsHideTimer == null)) {
                  _armChannelsHide();
                }
                return SafeArea(
                  child: SizedBox(
                    width: 220,
                    height: double.infinity,
                    child: ExcludeFocus(
                      excluding: !interactive,
                      child: AnimatedSlide(
                        offset: visible ? Offset.zero : const Offset(1, 0),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: IgnorePointer(
                          ignoring: !interactive,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              if (interactive) _markChannelsActivity();
                              return false;
                            },
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ListenableBuilder(
                                listenable: _channelController,
                                builder: (context, _) => ChannelBar(
                                  channels: widget.channels,
                                  selectedIndex: _channelController.index,
                                  onChanged: _channelController.select,
                                  onActivated: _activateChannelFromPanel,
                                  visible: visible,
                                  interactive: interactive,
                                ),
                              ),
                            ),
                          ),
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            WeatherNowPanel(),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  sourceTips,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Column(
                              children: [
                                DirectionWidget(
                                  hotUp: true,
                                  hotDown: true,
                                  size: 52,
                                ),
                                Text(
                                  'iptv_hint_change_channel'.tr(),
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(width: 8),
                            Column(
                              children: [
                                DirectionWidget(
                                  hotLeft: true,
                                  hotRight: true,
                                  size: 52,
                                ),
                                Text(
                                  'iptv_hint_change_source'.tr(),
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(width: 8),
                            Column(
                              children: [
                                DirectionWidget(hotOk: true, size: 52),
                                Text(
                                  'iptv_hint_channel_list'.tr(),
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(width: 8),
                            _ClockPanel(color: textColor),
                            SizedBox(width: 8),
                            WeatherDaysPanel(),
                          ],
                        ),
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
        final ChannelNumberInputController input =
            ChannelNumberInputController.instance;
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
              fontFeatures: outOfRange
                  ? null
                  : const <FontFeature>[FontFeature.tabularFigures()],
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
  const _AudioNowPlaying({
    required this.label,
    required this.visible,
    required this.barsActive,
  });

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
    final String sourceTips = lines.length > 1
        ? lines.sublist(1).join(' ')
        : '';
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
                  builder: (BuildContext context, bool active, Widget? _) =>
                      _EqualizerBars(active: active),
                ),
              ),
            ),
          ),
          // 前景信息：所有内容参与真实布局，空间不足时局部缩小，不再用
          // Transform.scale 放大绘制区域造成横向和纵向 overflow。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _ClockPanel(
                        color: Colors.white,
                        timeSize: timeSize,
                        horizontalSize: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Icon(
                      Icons.radio_rounded,
                      size: iconSize,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: nameSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (sourceTips.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        sourceTips,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: tipsSize,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          WeatherNowPanel(),
                          SizedBox(width: 24),
                          WeatherDaysPanel(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

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
      painter: _EqualizerBarsPainter(
        animation: _controller,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    );
  }
}

/// 声条绘制：把时间轴映射成每条柱子的高度。
class _EqualizerBarsPainter extends CustomPainter {
  _EqualizerBarsPainter({required this.animation, required this.color})
    : super(repaint: animation);

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
          0.5 * math.sin(t + phase) +
          0.3 * math.sin(t * 1.7 + phase * 1.6) +
          0.2 * math.sin(t * 3.1 + phase * 0.7);
      final double ratio = _minRatio + (1 - _minRatio) * ((wave + 1) / 2);
      final double barHeight = size.height * ratio;
      final double left = i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  /// 逐帧重绘由 `super(repaint: animation)` 驱动，这里只比较静态属性。
  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 时钟：`HH:mm:ss` + `年月日 农历 星期`，每秒刷新。
///
/// 时刻做成独立 StatefulWidget：定时刷新只重建这一小块，避免每秒
/// `setState` 波及上层 Stack 里的 [Video]，造成播放器反复重建。
class _ClockPanel extends StatefulWidget {
  const _ClockPanel({
    required this.color,
    this.timeSize = 32,
    this.horizontalSize = false,
  });

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
    final LunarDate? lunar = lunarDateOf(
      DateTime(_now.year, _now.month, _now.day),
    );
    final String subtitle = <String>[_dateFmt.format(_now)].join(' ');
    final String dateInChina = <String>[
      if (lunar != null) lunar.fullCnString,
      _weekdayFmt.format(_now),
    ].join(' ');
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

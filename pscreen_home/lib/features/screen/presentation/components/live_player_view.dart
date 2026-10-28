import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';
import 'package:pscreen_screen/features/iptv/application/playback_retry_controller.dart';
import 'package:pscreen_screen/features/iptv/application/playback_watchdog.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';

/// 触屏版直播播放器：负责「打开当前频道 + 视频铺满 + 音频台识别」。
///
/// 与电视端 `LivePlayerWidget` 的差异：不做遥控焦点 / 频道条 / 代理池等
/// TV 专属逻辑。频道切换统一走共享包的 [LiveChannelController]
/// （触屏点选走 `select`，立即提交播放，不延迟）。
///
/// 播放失败重试 / 看门狗 / 媒体类型判定统一复用共享包三件套
/// （[PlaybackRetryController] / [PlaybackWatchdog] / [MediaKindProbe]），
/// 与电视端行为一致：多源循环回退、一轮退避 1→2→4→8s、打开后无画面超时回退；
/// 触屏仅直连（不注入换路由），看门狗超时固定 60 秒。
/// 判定为音频时叠加「正在播放」层（收音机图标 + 频道名 + 贴底跳动声条氛围层）。
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
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<AudioParams>? _audioParamsSub;

  /// 播放失败重试状态机（共享包）：冷却 / 多源循环回退 / 一轮退避 1→2→4→8s。
  late final PlaybackRetryController _retry;

  /// 媒体类型判定（共享包）：只看真实轨道区分音频台 / 视频台。
  late final MediaKindProbe _probe;

  /// 「打开后长时间无画面」看门狗（共享包）：超时固定 [_watchdogTimeout]。
  late final PlaybackWatchdog _watchdog;

  /// 打开后多久没进入播放 / 没出画面即判坏源回退（与电视端直连一致）。
  static const Duration _watchdogTimeout = Duration(seconds: 60);

  /// 当前源的媒体类型判定结果（真值在共享判定器里，见 [MediaKindProbe.kind]）。
  /// 默认 [MediaKind.unknown] → 按视频（严格）处理，拿到确凿证据才改结论。
  MediaKind get _mediaKind => _probe.kind;

  /// 音频输出参数就绪 → 音频节目「确实在出声」的证据。
  bool get _audioParamsReady => _probe.audioParamsReady;

  /// 声条是否跳动（判定为音频且确实在出声才为 true）。
  final ValueNotifier<bool> _barsActiveVN = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    // ---- 共享包三件套（媒体判定 / 看门狗 / 重试状态机），先建再挂订阅 ----
    _probe = MediaKindProbe(onChanged: _onProbeChanged);
    _watchdog = PlaybackWatchdog(
      probe: _probe,
      isPlaying: () => _player.state.playing,
      onIssue: (String reason) => _onIssue(reason: reason),
      timeoutOf: () => _watchdogTimeout,
    );
    _retry = PlaybackRetryController(
      sourceCount: _currentSourceCount,
      open: _openSource,
      // 失败现场（换源之前）：上报 play_retry，防刷屏由上报服务限流。
      onEnterRetry: (String reason) => _report('play_retry', reason: reason),
      // 触屏仅直连：不注入换路由（电视端的代理池才需要）。
      isActive: () => mounted,
    );
    ChannelInfoProvider.instance.setChannels(widget.channels);
    LiveChannelController.instance.setCount(widget.channels.length);
    LiveChannelController.instance.onPlayCommit.addListener(_openCurrent);
    // ---- 播放状态上报 + 重试状态机事件喂入 ----
    // 进入播放：本轮退避清零；推进看门狗结算；按电视端标准报成功
    // （视频要出过真实画面帧，音频要已判定为音频）。
    _playingSub = _player.stream.playing.listen((bool value) {
      if (value) _retry.resetRound();
      _watchdog.notifyState();
      // 音频节目「已出声」的证据之一 → 声条可以开始跳。
      _syncBarsActive();
      if (value) _maybeReportOk();
    });
    // 播放失败：进重试状态机（冷却过滤 → 报 play_retry → 循环回退到下一个源）。
    // 忽略与电视端同组的非致命 seek 报错。
    _errorSub = _player.stream.error.listen((String msg) {
      final String trimmed = msg.trim();
      if (trimmed.contains('Cannot seek in this stream') || trimmed.contains('--force-seekable')) {
        return;
      }
      final String detail = trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
      // 真实 open 失败跳过冷却，允许连续打不开的源一路回退。
      _onIssue(reason: 'error: $detail', bypassCooldown: true);
    });
    // 直播流被对端断开且无 error 时会走到 completed，同样进重试。
    _completedSub = _player.stream.completed.listen((bool done) {
      if (done) _onIssue(reason: 'completed=true');
    });
    // ---- 媒体类型判定（共享判定器：只看真实轨道，不看地址/名称）----
    // 规则（排除 auto/no 伪轨与封面图、空表不作数、音频立即下结论、兜底窗口）
    // 都在共享包 [MediaKindProbe] 里；轨道表是判定主入口。
    _tracksSub = _player.stream.tracks.listen((Tracks tracks) {
      if (!mounted) return;
      _probe.handleTracks(tracks);
      // 判定可能刚落定 → 推进挂起的看门狗结算。
      _watchdog.notifyState();
    });
    // 出过视频帧（width>0）→ 有画面即确认是视频节目（可推翻音频误判），
    // 「打开后无画面」看门狗随即解除。
    _widthSub = _player.stream.width.listen((int? w) {
      if (!mounted) return;
      if (w != null && w > 0) {
        _probe.handleWidth(w);
        _watchdog.cancel();
        // 有真实画面 = 视频节目播放成功。
        _maybeReportOk();
      }
    });
    // 音频输出参数就绪 → 音频节目「确实在出声」的证据，声条开始跳。
    _audioParamsSub = _player.stream.audioParams.listen((AudioParams p) {
      if (!mounted) return;
      if (p.channelCount != null || p.sampleRate != null || p.format != null) {
        _probe.handleAudioParams(p);
        _watchdog.notifyState();
        _syncBarsActive();
        if (_mediaKind == MediaKind.audio) _maybeReportOk();
      }
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
    _tracksSub?.cancel();
    _widthSub?.cancel();
    _audioParamsSub?.cancel();
    _watchdog.dispose();
    _probe.dispose();
    _barsActiveVN.dispose();
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
      if (channel.sources.isEmpty) return;
      // 源号 / 轮次取重试状态机的现场值（与电视端一致）。
      final int idx = _retry.sourceIndex.clamp(0, channel.sources.length - 1);
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

  /// 播放成功判定（与电视端同标准）：视频要出过真实画面帧（width>0），
  /// 音频要已进入播放且类型已判定为音频。
  void _maybeReportOk() {
    final bool playing = _player.state.playing;
    if (_probe.playedVideo || (_mediaKind == MediaKind.audio && playing)) {
      _report('play_ok');
    }
  }

  /// 媒体类型判定结论变化（共享判定器 [_probe] 的 onChanged 回调）：
  /// 刷新界面（音频层要显示/淡出收音机界面）并同步声条。
  ///
  /// 必须在判定回调里 setState：这些回调不经过 build，
  /// 不 setState 的话音频界面要等到别的重建时机才出现。
  void _onProbeChanged(MediaKind kind) {
    if (mounted) setState(() {});
    _syncBarsActive();
  }

  /// 声条是否跳动：只有**已经断定是音频、而且确实出声了**才跳。
  ///
  /// - [MediaKind.unknown]（还在连接）或视频节目 → 不跳；
  /// - 音频且已出声（进入播放 / 音频输出参数就绪）→ 跳。
  void _syncBarsActive() {
    final bool outputReady = _audioParamsReady || _player.state.playing;
    final bool active = _mediaKind == MediaKind.audio && outputReady;
    if (_barsActiveVN.value != active) _barsActiveVN.value = active;
  }

  /// 音频整屏的频道名与源序号（形如 `甘肃新闻综合\n源 1/2`），
  /// 源号取重试状态机的当前源。
  String _channelLabel() {
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return '';
    final IptvChannel channel = widget.channels[index];
    if (channel.sources.isEmpty) return channel.name;
    final int i = _retry.sourceIndex.clamp(0, channel.sources.length - 1) + 1;
    return '${channel.name}\n源 $i/${channel.sources.length}';
  }

  /// 当前频道的源总数（重试状态机的 `sourceCount` 回调）。
  int _currentSourceCount() {
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return 0;
    return widget.channels[index].sources.length;
  }

  /// 换台（触屏点选 / 首次进入）：源序号回 0、本轮退避清零，
  /// 并推进世代号让退避中的过期回退自动作废，随后打开首源。
  void _openCurrent() {
    if (!mounted) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    if (widget.channels[index].sources.isEmpty) return;
    _retry.resetForChannel(0);
    // 换台期间抑制旧流残留的 error/completed 干扰（与电视端一致）。
    _retry.setBusy(true);
    unawaited(
      _openSource(_retry.sourceIndex).whenComplete(() => _retry.setBusy(false)),
    );
  }

  /// 打开当前频道的第 [sourceIndex] 个源（重试状态机的 open 回调）。
  Future<void> _openSource(int sourceIndex) async {
    if (!mounted) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    final IptvChannel channel = widget.channels[index];
    if (channel.sources.isEmpty) return;
    final int idx = sourceIndex.clamp(0, channel.sources.length - 1);
    final String url = channel.sources[idx];
    if (url.isEmpty) return;
    // 换源后媒体类型重新判定：地址/名称都不作依据，只看新源的真实轨道；
    // 声条一并停掉（此刻 playing 很可能还是上一个源的值，会误判成「已出声」）。
    _probe.reset();
    _barsActiveVN.value = false;
    _watchdog.arm();
    _lastOpenAt = DateTime.now();
    // 刷新重试状态机的 700ms 冷却基准。
    _retry.markOpen();
    try {
      // 确保解码方式（软解/硬解）已应用到播放器（mpv 的 hwdec 需在 open 前设置才生效）。
      await _applyHwdecSetting();
      await _player.open(Media(url));
      _report('play_start', index: index);
    } catch (_) {
      // 打开失败由 error 流 / 看门狗进入重试；不向上抛，避免卡住状态机的 busy 位。
    }
  }

  /// 应用解码方式设置（软解/硬解）：每次打开前读取最新设置（默认软解，
  /// 与电视端一致），设置页切换后下次换台/换源即生效。
  Future<void> _applyHwdecSetting() async {
    try {
      await AppSettings.instance.ensureLoaded();
      if (_player.platform is! NativePlayer) return;
      final bool enabled = AppSettings.instance.hwdecEnabled;
      await (_player.platform as NativePlayer).setProperty('hwdec', enabled ? 'auto' : 'no');
    } catch (_) {
      // 设置失败不阻断播放（回落 mpv 默认解码方式）。
    }
  }

  /// 播放失败/结束/看门狗到期：交给共享重试状态机（冷却过滤 → 报 play_retry
  /// → 一轮退避 → 循环回退到下一个源）。触屏仅直连，不注入换路由回调。
  void _onIssue({String reason = '', bool bypassCooldown = false}) {
    unawaited(_retry.handleIssue(reason: reason, bypassCooldown: bypassCooldown));
  }

  @override
  Widget build(BuildContext context) {
    // 黑底铺满父级，视频按 contain 自适应（不同画幅的流都完整显示、留边）。
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(
            controller: _videoController,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
          // 音频节目（广播台）没有画面：居中收音机图标 + 频道名，
          // 贴底叠一层跳动声条氛围。只在判定为音频时淡入显示
          // （unknown / 视频保持原画面），且不可点击、不影响浮层交互。
          Positioned.fill(
            child: IgnorePointer(
              child: _AudioNowPlaying(
                label: _channelLabel(),
                visible: _mediaKind == MediaKind.audio,
                barsActive: _barsActiveVN,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 音频节目（广播台）的「正在播放」层（与电视端 `_AudioNowPlaying` 同排版，
/// 触屏版不含时钟 / 天气行）：
/// ```text
///              📻              ← 收音机图标
///            甘肃新闻综合        ← 频道名
///              源 1/2
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
  /// `_LivePlayerViewState._channelLabel()` 生成）。
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
    // 以短边为基准缩放，横竖屏都协调。
    final Size size = MediaQuery.sizeOf(context);
    final double shortSide = size.shortestSide;
    final double iconSize = (shortSide * 0.11).clamp(56.0, 132.0);
    final double nameSize = (shortSide * 0.042).clamp(24.0, 54.0);
    final double tipsSize = (shortSide * 0.026).clamp(16.0, 32.0);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 氛围层：贴底的跳动声条。低透明度，只做背景，不抢前景信息。
          // 用 ValueListenableBuilder 局部刷新：播放状态变化只重建这一层。
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
          // 前景信息：收音机图标 + 频道名 + 源序号，纵向居中。
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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
          ),
        ],
      ),
    );
  }
}

/// 跳动声条（音频界面的背景氛围层）。
///
/// **是模拟动画，不是真实频谱**：取真实频谱需要从原生侧拿 PCM 数据做 FFT，
/// 而 media_kit/mpv 没有把这层暴露给 Dart；对「正在播放」的氛围表达，
/// 多条不同频率正弦叠加已经足够，且零依赖、可控开销。
///
/// [active] 为 false 时停掉动画：该层始终留在树上（做淡入淡出），
/// 不主动停会导致「连接中/不播音频」时也在后台逐帧空转。
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.active});

  /// 是否让声条跳动（判定为音频节目且确实出声了才为 true）。
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

  /// 柱子数量：够密才有氛围，又不至于在低端设备上浪费绘制。
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

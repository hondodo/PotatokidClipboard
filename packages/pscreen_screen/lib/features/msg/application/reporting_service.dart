import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 上行发送抽象（生产为实时通道；测试用 Fake）。
abstract class MessageSender {
  Future<bool> sendText({required String toAccount, required String text});

  /// 发送结构化事件。旧实现可保持默认返回 false，不影响文本上报。
  Future<bool> sendEvent({
    required String toAccount,
    required String event,
    Map<String, Object?>? data,
  }) async =>
      false;
}

/// 上行上报服务（设计 §3.2/§5.5）：登录两条、切台防抖、5 分钟心跳。
class ReportingService {
  ReportingService({
    required this.sender,
    required this.deviceModel,
    required this.channelInfo,
    required this.liveChannel,
    required this.sceneProvider,
    DateTime Function()? now,
    Duration? heartbeatInterval,
  })  : _now = now ?? DateTime.now,
        _heartbeatInterval =
            heartbeatInterval ?? ReportingService.heartbeatInterval {
    _playCommitListener = () => notifyChannelCommitted();
    liveChannel.onPlayCommit.addListener(_playCommitListener);
  }

  /// 系统管理员账号。
  static const String adminAccount = '1000001';

  /// 心跳间隔（默认 5 分钟，测试可注入短间隔）。
  static const Duration heartbeatInterval = Duration(minutes: 5);

  /// 切台确认防抖。
  static const Duration channelDebounce = Duration(seconds: 1);

  /// 播放失败重试上报的限流窗口：坏台按 1~8s 反复重试，
  /// 连续 `play_retry` 至少间隔这段时间才发一条（首条不受限）。
  static const Duration playbackRetryThrottle = Duration(seconds: 30);

  final MessageSender sender;
  final Future<String> Function() deviceModel;
  final ChannelInfoProvider channelInfo;
  final LiveChannelController liveChannel;

  /// 当前场景描述提供者（由宿主注入）。
  final CurrentSceneProvider sceneProvider;

  final DateTime Function() _now;

  /// 实际生效的心跳间隔（构造时可覆盖，默认 [heartbeatInterval]）。
  final Duration _heartbeatInterval;

  late final VoidCallback _playCommitListener;

  Timer? _heartbeat;
  Timer? _channelTimer;
  Timer? _sceneTimer;
  Listenable? _sceneChanges;
  String? _lastSceneKey;
  String? _lastChannelName;
  DateTime? _loginAt;
  bool _started = false;
  String? _model;

  // ---- 播放状态上报（play_*）的本地去重状态 ----
  /// 上次涉及的频道：换台即清空下面的去重记录（新频道重新开始）。
  String? _pbChannel;

  /// 本频道已报过 `play_start` 的源（同频道每源只报首次，代理重试不重复报）。
  final Set<String> _pbStartedKeys = <String>{};

  /// 上次已发送的播放状态：同频道连续重复的 `play_ok`/`play_fail` 直接丢弃
  /// （视频帧与 playing 可能先后各触发一次成功，只报第一条）。
  String _pbLastState = '';

  /// 上次发送 `play_retry` 的时间（限流用）。
  DateTime? _pbRetryAt;

  /// 场景切换防抖：路由 push/pop 常连续触发，只上报最终落点。
  static const Duration sceneDebounce = Duration(milliseconds: 250);

  /// 启动纪元：stop/重启时自增，使仍在 await 中的 start 作废。
  int _epoch = 0;

  /// 登录成功（RemoteLoginState.loggedIn 边沿）时调用；先取设备型号再发前两条。
  Future<void> start(String account) async {
    if (_started) return;
    _started = true;
    final int epoch = ++_epoch;
    final DateTime loginAt = _now();
    _loginAt = loginAt;
    final String model = await deviceModel();
    if (!_started || epoch != _epoch) return; // await 期间 stop/重启
    _model = model;
    _send('$account于${_fmt(loginAt)}使用$_deviceModelCache登录成功。');
    _send(_sceneLoginText());
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _onHeartbeat());

    // 场景变化订阅：只有宿主提供 changes 时才启用。
    final SceneSnapshot initialScene = _snapshot();
    _lastSceneKey = initialScene.key;
    _lastChannelName =
        initialScene.kind == SceneKind.live ? initialScene.channelName : null;
    // 除了聊天里的登录文案，再落一条结构化初始场景，便于后台直接按场景检索。
    reportEvent('scene_changed', initialScene.toJson());
    try {
      final Listenable? changes = sceneProvider.changes;
      _sceneChanges = changes;
      changes?.addListener(_onSceneChanged);
    } catch (e) {
      // 宿主尚未完成初始化时降级为只上报登录/心跳，不能影响连接。
      Log.i('[ReportingService] 场景变化订阅失败: $e');
    }
  }

  /// 登出/停止（error/notConfigured 边沿、dispose 时）。
  void stop() {
    _epoch++; // 作废在途的 start
    _started = false;
    _loginAt = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _channelTimer?.cancel();
    _channelTimer = null;
    _sceneTimer?.cancel();
    _sceneTimer = null;
    _sceneChanges?.removeListener(_onSceneChanged);
    _sceneChanges = null;
    _lastSceneKey = null;
    _lastChannelName = null;
    // 重新登录后播放去重记录从头开始（避免旧频道的去重状态吞掉新事件）。
    _pbChannel = null;
    _pbStartedKeys.clear();
    _pbLastState = '';
    _pbRetryAt = null;
  }

  /// 切台确认（onPlayCommit 钩子）：防抖后发「切换频道」。
  ///
  /// 旧宿主（[SceneKind.unknown]）保持原行为；结构化宿主只在直播场景上报，
  /// 并按频道名去重，避免进入直播页恢复上次频道时误报。
  void notifyChannelCommitted() {
    if (!_started) return;
    final SceneSnapshot scene = _snapshot();
    if (scene.kind != SceneKind.unknown && scene.kind != SceneKind.live) return;
    _channelTimer?.cancel();
    _channelTimer = Timer(channelDebounce, () {
      _channelTimer = null;
      // 防抖期间可能已经离开直播页，定时器触发时以最新场景为准。
      final SceneSnapshot current = _snapshot();
      if (current.kind != SceneKind.unknown && current.kind != SceneKind.live) {
        return;
      }
      final String? name = channelInfo.nameAt(liveChannel.index);
      if (name == null || name == _lastChannelName) return;
      _lastChannelName = name;
      _send('切换频道：$name');
      reportEvent('channel_changed', <String, Object?>{
        'channelName': name,
        'index': liveChannel.index,
        'scene': current.toJson(),
      });
    });
  }

  /// 上报播放状态（纯观测：宿主在播放器的 open/成功/失败回调处调用）。
  ///
  /// [state] 取值：
  /// - `play_start`：选中某源并 open（同频道同源只报首次）；
  /// - `play_ok`：确认进入可播状态（连续重复丢弃）；
  /// - `play_retry`：播放失败进入重试（限流 [playbackRetryThrottle]，首条立即）；
  /// - `play_fail`：终态失败（宿主无重试时用，连续重复丢弃）。
  ///
  /// 去重/限流全部在本方法内完成，宿主无需关心防刷屏；
  /// 任何异常自行吞掉，绝不影响调用方的播放链路。
  void notifyPlayback(
    String state, {
    required String channel,
    int sourceIndex = 0,
    int sourceTotal = 0,
    String sourceUrl = '',
    String reason = '',
    int round = 0,
    bool viaProxy = false,
    Duration? elapsed,
  }) {
    if (!_started || channel.isEmpty) return;
    try {
      // 换台 = 全新上下文：源去重表与限流记录一并重置。
      if (channel != _pbChannel) {
        _pbChannel = channel;
        _pbStartedKeys.clear();
        _pbLastState = '';
        _pbRetryAt = null;
      }
      if (state == 'play_start') {
        // 每个源在本频道内只报首次 open：退避后重开同源、同一代理的重复尝试
        // 都不重复；但「直连 → 改代理重试」算一条新信息，单独放行一次。
        if (!_pbStartedKeys.add('$sourceIndex/$sourceTotal/$sourceUrl${viaProxy ? '@proxy' : ''}')) {
          // 重开已报过的源 = 新一轮尝试：允许随后的 ok/fail 再次上报
          //（否则「失败 → 重新打开同源 → 再失败」的后续失败会被当成连续重复吞掉）。
          _pbLastState = '';
          return;
        }
      } else if (state == 'play_retry') {
        // 坏台会以 1~8s 的节奏无限重试：首条立即发（让人知道在重试），
        // 之后按限流窗口发，恢复（play_ok）会重置状态使下一条立即可发。
        final DateTime now = _now();
        if (_pbRetryAt != null && now.difference(_pbRetryAt!) < playbackRetryThrottle) {
          return;
        }
        _pbRetryAt = now;
      } else if (state == _pbLastState) {
        return; // play_ok / play_fail 同频道连续重复
      }
      // 恢复/终态后，下一次失败的首条 retry 不再受上次限流影响（立刻可报）。
      if (state == 'play_ok' || state == 'play_fail') _pbRetryAt = null;
      _pbLastState = state;
      reportEvent(state, <String, Object?>{
        'channelName': channel,
        'sourceIndex': sourceIndex,
        'sourceTotal': sourceTotal,
        'source': _shortSource(sourceUrl),
        'round': round,
        if (viaProxy) 'viaProxy': true,
        if (reason.isNotEmpty) 'reason': reason.length > 120 ? '${reason.substring(0, 120)}…' : reason,
        if (elapsed != null) 'elapsedMs': elapsed.inMilliseconds,
      });
    } catch (e) {
      Log.error('[ReportingService] 播放状态上报异常: $e');
    }
  }

  /// 源地址脱敏截断：只留 `scheme://host/path`（丢弃可能带 token 的 query），
  /// 无法解析时截到 128 字符——够用来认出「哪个源」，又不至于刷屏。
  static String _shortSource(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    try {
      final Uri uri = Uri.parse(trimmed);
      if (uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}${uri.path}';
      }
    } catch (_) {}
    return trimmed.length > 128 ? '${trimmed.substring(0, 128)}…' : trimmed;
  }

  /// 当前位置文本：由注入的场景描述器决定（各宿主自行决定「频道名还是页名」）。
  String positionText() => _snapshot().title;

  String get _deviceModelCache => _model ?? 'Android TV';

  void _onHeartbeat() {
    if (!_started || _loginAt == null) return;
    final int minutes = _now().difference(_loginAt!).inMinutes;
    final SceneSnapshot scene = _snapshot();
    if (scene.kind == SceneKind.unknown) {
      _send('已收看$minutes分钟，当前频道是${scene.title}');
    } else {
      _send('已在线$minutes分钟，当前场景：${scene.title}');
    }
  }

  /// 上报任意结构化事件（HA 操作、场景变化等）。
  ///
  /// 服务端按 `t:'event'` 落库，不进入聊天历史；在线目标会实时收到。
  void reportEvent(String event, Map<String, Object?> data) {
    if (!_started) return;
    sender
        .sendEvent(toAccount: adminAccount, event: event, data: data)
        .then((bool ok) {
      if (!ok) Log.i('[ReportingService] 事件上报失败: $event');
    }).catchError((Object e) {
      Log.error('[ReportingService] 事件上报异常: $e');
    });
  }

  /// 上报链路不能因宿主路由/DI 尚未就绪而抛异常。
  SceneSnapshot _snapshot() {
    try {
      return sceneProvider.snapshot();
    } catch (_) {
      return const SceneSnapshot(kind: SceneKind.unknown, title: '未知场景');
    }
  }

  String _sceneLoginText() {
    final SceneSnapshot scene = _snapshot();
    if (scene.kind == SceneKind.unknown) return '正在收看${scene.title}';
    return '已登录，当前场景：${scene.title}';
  }

  void _onSceneChanged() {
    if (!_started) return;
    _sceneTimer?.cancel();
    _sceneTimer = Timer(sceneDebounce, _flushSceneChange);
  }

  void _flushSceneChange() {
    _sceneTimer = null;
    if (!_started) return;
    final SceneSnapshot scene = _snapshot();
    if (scene.key == _lastSceneKey) return;
    _lastSceneKey = scene.key;
    _send('场景切换：${scene.title}');
    reportEvent('scene_changed', scene.toJson());

    final String? channel = scene.channelName;
    if (scene.kind == SceneKind.live && channel != null && channel.isNotEmpty) {
      final String? previous = _lastChannelName;
      _lastChannelName = channel;
      if (previous != null && previous != channel) {
        reportEvent('channel_changed', <String, Object?>{
          'channelName': channel,
          'scene': scene.toJson(),
        });
      }
    } else if (scene.kind != SceneKind.live) {
      _lastChannelName = null;
    }
  }

  void _send(String text) {
    sender.sendText(toAccount: adminAccount, text: text).then((bool ok) {
      if (!ok) Log.i('[ReportingService] 上报发送失败: $text');
    }).catchError((Object e) {
      Log.error('[ReportingService] 上报异常: $e');
    });
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  void dispose() {
    stop();
    liveChannel.onPlayCommit.removeListener(_playCommitListener);
  }
}

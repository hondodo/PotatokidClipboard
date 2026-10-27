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

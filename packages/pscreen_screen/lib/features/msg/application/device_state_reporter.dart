import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 被控端状态上报（`state` 帧）。
///
/// - 场景变化：防抖后推送场景快照（~几百字节）；
/// - 频道列表：只有版本（FNV-1a 摘要）变化时才随 `state` 下发完整名单，
///   首次连接/服务端重启后整体重发一次；
/// - 断线期间不缓存，重连成功立即整体重发。
///
/// 控制端通过 `watch` 订阅后由服务端转发，不需要向设备反查。
class DeviceStateReporter {
  DeviceStateReporter({
    required this.channel,
    required this.sceneProvider,
    this.listCheckInterval = const Duration(seconds: 10),
  });

  final RealtimeChannel channel;
  final CurrentSceneProvider sceneProvider;

  /// 列表变化轮询间隔（频道列表加载通常不伴随场景变化）。
  final Duration listCheckInterval;

  /// 场景切换防抖：路由 push/pop 常连续触发，只推送最终落点。
  static const Duration sceneDebounce = Duration(milliseconds: 250);

  StreamSubscription<RealtimeConnectionState>? _connSub;
  Timer? _debounce;
  Timer? _listTimer;
  Listenable? _sceneChanges;
  String? _lastListVersion;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _connSub = channel.connectionState.listen((RealtimeConnectionState s) {
      if (s == RealtimeConnectionState.connected) {
        // 新连接（含服务端重启）：丢弃旧的列表版本，整体重发。
        _lastListVersion = null;
        _push(full: true);
        _startListWatch();
      } else if (s == RealtimeConnectionState.disconnected ||
          s == RealtimeConnectionState.error) {
        _stopListWatch();
        _lastListVersion = null;
      }
    });
    try {
      _sceneChanges = sceneProvider.changes;
      _sceneChanges?.addListener(_onSceneChanged);
    } catch (e) {
      // 宿主尚未初始化时降级为仅列表变化时上报，不能影响连接。
      Log.i('[DeviceStateReporter] 场景订阅失败: $e');
    }
    // 注册时通道可能已经连上（错过 connectionState 事件）。
    if (channel.isConnected) {
      _push(full: true);
      _startListWatch();
    }
  }

  void stop() {
    _started = false;
    _connSub?.cancel();
    _connSub = null;
    _debounce?.cancel();
    _debounce = null;
    _stopListWatch();
    _sceneChanges?.removeListener(_onSceneChanged);
    _sceneChanges = null;
    _lastListVersion = null;
  }

  void _onSceneChanged() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(sceneDebounce, () => _push());
  }

  void _startListWatch() {
    _listTimer?.cancel();
    _listTimer = Timer.periodic(listCheckInterval, (_) {
      if (!channel.isConnected) return;
      final String version = _versionOf(_channelNames());
      if (version == _lastListVersion) return;
      _push();
    });
  }

  void _stopListWatch() {
    _listTimer?.cancel();
    _listTimer = null;
  }

  void _push({bool full = false}) {
    if (!_started || !channel.isConnected) return;
    try {
      final SceneSnapshot scene = sceneProvider.snapshot();
      final List<String> names = _channelNames();
      final String version = _versionOf(names);
      final bool sendList = full || version != _lastListVersion;
      if (sendList) _lastListVersion = version;
      channel.sendState(
        scene: scene.toJson(),
        channels: sendList ? names : null,
        listVersion: sendList ? version : null,
      );
    } catch (e) {
      Log.warn('[DeviceStateReporter] 状态上报异常: $e');
    }
  }

  static List<String> _channelNames() => ChannelInfoProvider.instance.channels
      .map((IptvChannel channel) => channel.name)
      .toList(growable: false);

  /// 频道名列表摘要（FNV-1a 32 位）：列表未变时避免重复下发近千条名称。
  static String _versionOf(List<String> names) {
    int hash = 0x811c9dc5;
    for (final String name in names) {
      for (final int code in name.codeUnits) {
        hash ^= code;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      hash ^= 0x0a;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

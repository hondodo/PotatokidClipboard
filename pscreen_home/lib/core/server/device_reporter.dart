import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/device/device_identity.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 中控屏与 Admin 服务端的同步器。
///
/// 职责：
/// - 启动时用 Android ID 注册设备，拉取「可见家庭」与首页布局；
/// - 在线期间通过实时通道（WebSocket）每 60 秒上报状态，并接收配置推送；
/// - WS 不可用时降级为每 5 分钟一次 HTTP 心跳，维持在线状态；
/// - 拖拽排序后把卡片顺序上传（带时间戳，服务端按新旧合并）；
/// - 服务端不可达时静默降级，不影响 HA 连接与主页使用。
class DeviceReporter {
  DeviceReporter({
    required SettingsStore store,
    required LogService log,
  }) : _store = store,
       _log = log;

  /// WS 上报间隔（与原 HTTP 心跳一致）。
  static const Duration _reportInterval = Duration(seconds: 60);

  /// WS 断开时的 HTTP 兜底间隔（降频，仅维持在线与配置自愈）。
  static const Duration _fallbackInterval = Duration(minutes: 5);

  final SettingsStore _store;
  final LogService _log;

  ServerApiClient? _client;
  String _deviceId = '';
  String _appVersion = '';
  String _layoutKey = '';
  int _layoutUpdatedAt = 0;

  Timer? _reportTimer;
  Timer? _fallbackTimer;
  Timer? _pushTimer;
  StreamSubscription<RealtimeConnectionState>? _wsStateSub;
  StreamSubscription<Map<String, dynamic>>? _wsConfigSub;

  /// null = 尚未判定过（首次 sync 必须真正执行一次，否则兜底不会启动）。
  bool? _wsReady;
  _PendingLayout? _pending;
  bool _initialized = false;

  /// 启动时调用一次（在 runApp 之前，保证布局先于 HomeBloc 创建生效）。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final String baseUrl = HaConfig.serverBaseUrl;
    if (baseUrl.isEmpty) {
      _log.info('[服务端] 未配置 SERVER_BASE_URL，跳过设备同步');
      return;
    }

    _client = ServerApiClient(baseUrl: baseUrl);
    _deviceId = await DeviceIdentity.deviceId();
    _appVersion = await _readAppVersion();
    final String model = await DeviceIdentity.model();

    try {
      final ServerDeviceConfig config = await _client!.registerDevice(
        deviceId: _deviceId,
        name: model,
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        model: model,
        appVersion: _appVersion,
      );
      _applyConfig(config, dispatch: false);
      _layoutKey = config.layoutKey;
      _layoutUpdatedAt = config.layoutUpdatedAt;
      await _syncLayout();
      _log.info(
        '[服务端] 设备已注册: $_deviceId 家庭来源=${config.source} '
        '布局=${config.layoutKey}',
      );
    } catch (error) {
      _log.warn('[服务端] 注册 / 拉取配置失败（将按 .env 运行）: $error');
    }
  }

  /// 启动在线上报（runApp 之后调用；未配置服务端时无操作）。
  ///
  /// 优先走实时通道（WS）：连接后每 60 秒上报一次；WS 未连通时降级为
  /// 每 5 分钟一次 HTTP 心跳，连通边沿自动切回 WS。
  void start() {
    if (_client == null) return;
    final RealtimeChannel? channel = _realtimeChannel;
    if (channel == null) {
      _startFallback();
      return;
    }
    _wsStateSub ??= channel.connectionState.listen((_) => _syncReportMode());
    _wsConfigSub ??= channel.deviceConfigs.listen(_applyServerConfig);
    _syncReportMode();
  }

  RealtimeChannel? get _realtimeChannel {
    if (!Injection.isRegistered<RealtimeChannel>()) return null;
    return Injection.get<RealtimeChannel>();
  }

  /// WS 连接状态变化：切换上报通道（进入连接态立即上报一次并拿到最新配置）。
  void _syncReportMode() {
    final bool ready = _realtimeChannel?.isConnected ?? false;
    if (ready == _wsReady) return;
    _wsReady = ready;
    _reportTimer?.cancel();
    _reportTimer = null;
    if (ready) {
      _stopFallback();
      _reportTimer = Timer.periodic(
        _reportInterval,
        (_) => unawaited(_reportViaWs()),
      );
      unawaited(_reportViaWs());
    } else {
      _startFallback();
    }
  }

  void _startFallback() {
    _fallbackTimer?.cancel();
    // 不立即发：启动注册已完成一次配置同步，首个兜底心跳等一个周期即可，
    // 避免 WS 正常时也产生一次 HTTP 心跳。
    _fallbackTimer = Timer.periodic(
      _fallbackInterval,
      (_) => unawaited(_heartbeat()),
    );
  }

  void _stopFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// 设置页修改服务端地址后调用：断开旧客户端并重新注册 / 同步。
  Future<void> reinitialize() async {
    _cancelTimers();
    _cancelWsSubscriptions();
    _pending = null;
    _client?.dispose();
    _client = null;
    _deviceId = '';
    _layoutKey = '';
    _layoutUpdatedAt = 0;
    _initialized = false;
    await initialize();
    start();
  }

  void dispose() {
    _cancelTimers();
    _cancelWsSubscriptions();
    _client?.dispose();
    _client = null;
  }

  void _cancelTimers() {
    _reportTimer?.cancel();
    _reportTimer = null;
    _stopFallback();
    _pushTimer?.cancel();
    _wsReady = null;
  }

  void _cancelWsSubscriptions() {
    _wsStateSub?.cancel();
    _wsStateSub = null;
    _wsConfigSub?.cancel();
    _wsConfigSub = null;
  }

  /// WS 上报：状态字段 + 回包里的最新配置（服务端顺带刷新 lastSeen）。
  Future<void> _reportViaWs() async {
    final RealtimeChannel? channel = _realtimeChannel;
    if (channel == null || !channel.isConnected) return;
    try {
      final Map<String, dynamic>? config = await channel.sendReport(
        knownHomes: _knownHomes(),
        currentHome: _currentHome(),
        haConnected: _haConnected(),
        appVersion: _appVersion,
      );
      if (config != null) _applyServerConfig(config);
    } catch (error) {
      _log.info('[服务端] ws 上报失败: $error');
    }
  }

  /// 兜底：WS 未连通时的降频 HTTP 心跳。
  Future<void> _heartbeat() async {
    final ServerApiClient? client = _client;
    if (client == null || _deviceId.isEmpty) return;
    try {
      final ServerDeviceConfig config = await client.heartbeat(
        deviceId: _deviceId,
        appVersion: _appVersion,
        knownHomes: _knownHomes(),
        currentHome: _currentHome(),
        haConnected: _haConnected(),
      );
      _applyConfig(config, dispatch: true);
    } catch (error) {
      // 心跳失败很常见（服务端重启 / 设备离线），只记 info 级日志。
      _log.info('[服务端] 心跳失败: $error');
    }
  }

  /// 服务端推送 / 上报回包的配置：套用白名单，布局有更新时重新同步。
  void _applyServerConfig(Map<String, dynamic> json) {
    final ServerDeviceConfig config = ServerDeviceConfig.fromJson(json);
    _applyConfig(config, dispatch: true);
    if (config.layoutKey != _layoutKey ||
        (config.layoutUpdatedAt > 0 &&
            config.layoutUpdatedAt != _layoutUpdatedAt)) {
      _layoutKey = config.layoutKey;
      _layoutUpdatedAt = config.layoutUpdatedAt;
      unawaited(_syncLayout());
    }
  }

  void _applyConfig(ServerDeviceConfig config, {required bool dispatch}) {
    final String before = HaConfig.visibleHomes.join('\u0000');
    HaConfig.applyServerConfig(
      homes: config.homes,
      source: config.source,
      owner: config.owner,
      layoutKey: config.layoutKey,
    );
    final String after = HaConfig.visibleHomes.join('\u0000');
    if (!dispatch || before == after) return;
    _log.info('[服务端] 家庭白名单已更新: [$after]');
    if (Injection.isRegistered<HomeBloc>()) {
      Injection.get<HomeBloc>().add(
        ApplyHomeVisibility(HaConfig.visibleHomes),
      );
    }
  }

  List<String> _knownHomes() {
    if (!Injection.isRegistered<HomeBloc>()) return const <String>[];
    final Set<String> homes = <String>{};
    for (final area in Injection.get<HomeBloc>().state.registry.areas) {
      final String home = area.homeName.trim();
      if (home.isNotEmpty) homes.add(home);
    }
    return homes.toList(growable: false);
  }

  String _currentHome() {
    if (!Injection.isRegistered<HomeBloc>()) return '';
    return Injection.get<HomeBloc>().state.effectiveHomeName;
  }

  bool _haConnected() {
    if (!Injection.isRegistered<HomeBloc>()) return false;
    final state = Injection.get<HomeBloc>().state;
    return state.hasLoaded && !state.isFromCache;
  }

  /// 启动 / 布局归属变化时同步：服务端较新则覆盖本地，本地较新则上传。
  Future<void> _syncLayout() async {
    final ServerApiClient? client = _client;
    if (client == null || _deviceId.isEmpty) return;
    try {
      final ServerLayout remote = await client.fetchLayout(_deviceId);
      final int localUpdatedAt = _store.cardOrderUpdatedAt;
      final List<String> localAll = _store.cardOrderAll;
      final Map<String, List<String>> localByHome = _store.cardOrderByHome;
      final bool hasLocal = localAll.isNotEmpty || localByHome.isNotEmpty;

      if (remote.updatedAt > localUpdatedAt) {
        await _store.saveCardOrders(
          all: remote.all,
          byHome: remote.byHome,
          updatedAt: remote.updatedAt,
        );
        if (Injection.isRegistered<HomeBloc>()) {
          Injection.get<HomeBloc>().add(
            ApplyCardOrder(all: remote.all, byHome: remote.byHome),
          );
        }
        _log.info('[布局] 已从服务端恢复 ${remote.all.length} 张卡片顺序');
      } else if (localUpdatedAt > remote.updatedAt && hasLocal) {
        await client.putLayout(
          deviceId: _deviceId,
          all: localAll,
          byHome: localByHome,
          updatedAt: localUpdatedAt,
        );
        _log.info('[布局] 本地顺序已上传');
      }
    } catch (error) {
      _log.warn('[布局] 同步失败: $error');
    }
  }

  /// 拖拽后调用：合并 700ms 内的连续修改，避免每动一下都发请求。
  void pushLayout({
    required List<String> all,
    required Map<String, List<String>> byHome,
    required int updatedAt,
  }) {
    if (_client == null) return;
    _pending = _PendingLayout(
      all: List<String>.of(all),
      byHome: <String, List<String>>{
        for (final entry in byHome.entries)
          entry.key: List<String>.of(entry.value),
      },
      updatedAt: updatedAt,
    );
    _pushTimer?.cancel();
    _pushTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_flushPush()),
    );
  }

  Future<void> _flushPush() async {
    final ServerApiClient? client = _client;
    final _PendingLayout? pending = _pending;
    _pending = null;
    if (client == null || pending == null || _deviceId.isEmpty) return;
    try {
      final result = await client.putLayout(
        deviceId: _deviceId,
        all: pending.all,
        byHome: pending.byHome,
        updatedAt: pending.updatedAt,
      );
      if (result.conflict) {
        await _store.saveCardOrders(
          all: result.layout.all,
          byHome: result.layout.byHome,
          updatedAt: result.layout.updatedAt,
        );
        if (Injection.isRegistered<HomeBloc>()) {
          Injection.get<HomeBloc>().add(
            ApplyCardOrder(
              all: result.layout.all,
              byHome: result.layout.byHome,
            ),
          );
        }
        _log.warn('[布局] 服务端已有更新版本，已覆盖本地顺序');
      }
    } catch (error) {
      _log.warn('[布局] 上传失败，稍后重试: $error');
      _pending ??= pending;
      _pushTimer?.cancel();
      _pushTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(_flushPush()),
      );
    }
  }

  static Future<String> _readAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }
}

class _PendingLayout {
  const _PendingLayout({
    required this.all,
    required this.byHome,
    required this.updatedAt,
  });

  final List<String> all;
  final Map<String, List<String>> byHome;
  final int updatedAt;
}

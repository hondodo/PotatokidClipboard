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

/// 中控屏与 Admin 服务端的同步器。
///
/// 职责：
/// - 启动时用 Android ID 注册设备，拉取「可见家庭」与首页布局；
/// - 每 60 秒心跳上报在线状态 / 当前家庭 / 已知家庭，并接收配置变更；
/// - 拖拽排序后把卡片顺序上传（带时间戳，服务端按新旧合并）；
/// - 服务端不可达时静默降级，不影响 HA 连接与主页使用。
class DeviceReporter {
  DeviceReporter({
    required SettingsStore store,
    required LogService log,
  }) : _store = store,
       _log = log;

  final SettingsStore _store;
  final LogService _log;

  ServerApiClient? _client;
  String _deviceId = '';
  String _appVersion = '';
  String _layoutKey = '';

  Timer? _heartbeatTimer;
  Timer? _pushTimer;
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
      await _syncLayout();
      _log.info(
        '[服务端] 设备已注册: $_deviceId 家庭来源=${config.source} '
        '布局=${config.layoutKey}',
      );
    } catch (error) {
      _log.warn('[服务端] 注册 / 拉取配置失败（将按 .env 运行）: $error');
    }
  }

  /// 启动心跳（runApp 之后调用；未配置服务端时无操作）。
  void start() {
    if (_client == null) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_heartbeat()),
    );
    unawaited(_heartbeat());
  }

  /// 设置页修改服务端地址后调用：断开旧客户端并重新注册 / 同步。
  Future<void> reinitialize() async {
    _heartbeatTimer?.cancel();
    _pushTimer?.cancel();
    _pending = null;
    _client?.dispose();
    _client = null;
    _deviceId = '';
    _layoutKey = '';
    _initialized = false;
    await initialize();
    start();
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _pushTimer?.cancel();
    _client?.dispose();
    _client = null;
  }

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
      if (config.layoutKey.isNotEmpty && config.layoutKey != _layoutKey) {
        _layoutKey = config.layoutKey;
        await _syncLayout();
      }
    } catch (error) {
      // 心跳失败很常见（服务端重启 / 设备离线），只记 debug 级日志。
      _log.info('[服务端] 心跳失败: $error');
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

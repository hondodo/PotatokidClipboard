import 'dart:convert';

import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/registry_cache.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

/// 基于 SharedPreferences 的注册表缓存。
///
/// 缓存按 HA 地址隔离：切换服务器后不会误用旧家庭的房间 / 设备。
/// 只保存分组所需的最小字段，几十个设备的 JSON 体积很小。
class SettingsRegistryCache implements RegistryCache {
  SettingsRegistryCache({
    required SettingsStore store,
    required LogService log,
    String Function()? hostProvider,
  }) : _store = store,
       _log = log,
       _hostProvider = hostProvider ?? (() => HaConfig.haHost);

  static const int _version = 1;

  final SettingsStore _store;
  final LogService _log;
  final String Function() _hostProvider;

  @override
  HaRegistry? read() {
    final String raw = _store.registryCacheRaw;
    if (raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> payload = Map<String, dynamic>.from(decoded);
      if (payload['version'] != _version) return null;
      if (payload['host'] != _normalizeHost(_hostProvider())) {
        _log.debug('注册表缓存与当前 HA 地址不匹配，忽略缓存');
        return null;
      }
      final HaRegistry? registry = _decodeRegistry(payload);
      if (registry == null || registry.areas.isEmpty) return null;
      return registry;
    } catch (e) {
      _log.warn('读取注册表缓存失败，忽略缓存：$e');
      return null;
    }
  }

  @override
  Future<void> write(HaRegistry registry) async {
    // 没有房间时缓存对「家庭 / 房间」分组没有价值，跳过以免覆盖旧缓存。
    if (registry.areas.isEmpty) return;
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'version': _version,
        'host': _normalizeHost(_hostProvider()),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'areas': <Map<String, dynamic>>[
          for (final HaArea area in registry.areas)
            <String, dynamic>{
              'id': area.areaId,
              'name': area.name,
              'position': area.position,
            },
        ],
        'devices': <Map<String, dynamic>>[
          for (final HaDevice device in registry.devices.values)
            <String, dynamic>{
              'id': device.id,
              'name': device.name,
              if (device.areaId != null) 'areaId': device.areaId,
            },
        ],
        'areaIdByEntity': registry.areaIdByEntity,
        'deviceIdByEntity': registry.deviceIdByEntity,
      };
      await _store.saveRegistryCacheRaw(jsonEncode(payload));
    } catch (e) {
      _log.warn('写入注册表缓存失败：$e');
    }
  }

  static HaRegistry? _decodeRegistry(Map<String, dynamic> payload) {
    final Object? rawAreas = payload['areas'];
    if (rawAreas is! List) return null;
    final List<HaArea> areas = <HaArea>[];
    for (final Object? raw in rawAreas) {
      if (raw is! Map) continue;
      final Object? id = raw['id'];
      final Object? name = raw['name'];
      if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
        continue;
      }
      areas.add(
        HaArea(
          areaId: id,
          name: name,
          position: (raw['position'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    if (areas.isEmpty) return null;

    final Map<String, HaDevice> devices = <String, HaDevice>{};
    final Object? rawDevices = payload['devices'];
    if (rawDevices is List) {
      for (final Object? raw in rawDevices) {
        if (raw is! Map) continue;
        final Object? id = raw['id'];
        final Object? name = raw['name'];
        if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
          continue;
        }
        final Object? areaId = raw['areaId'];
        devices[id] = HaDevice(
          id: id,
          name: name,
          areaId: areaId is String && areaId.isNotEmpty ? areaId : null,
        );
      }
    }

    return HaRegistry(
      areas: List<HaArea>.unmodifiable(areas),
      devices: Map<String, HaDevice>.unmodifiable(devices),
      areaIdByEntity: _decodeStringMap(payload['areaIdByEntity']),
      deviceIdByEntity: _decodeStringMap(payload['deviceIdByEntity']),
    );
  }

  static Map<String, String> _decodeStringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final Map<String, String> out = <String, String>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String && value is String) out[key] = value;
    });
    return Map<String, String>.unmodifiable(out);
  }

  /// 同一台 HA 可能被写成 `http://host:8123` / `host:8123/`，
  /// 归一化后再比较，避免仅因写法不同导致缓存失效。
  static String _normalizeHost(String host) {
    String value = host.trim().toLowerCase();
    if (value.startsWith('http://')) {
      value = value.substring('http://'.length);
    } else if (value.startsWith('https://')) {
      value = value.substring('https://'.length);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

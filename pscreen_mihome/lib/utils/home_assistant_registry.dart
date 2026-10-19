import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Home Assistant WebSocket 注册表客户端。
///
/// `home_assistant` 包只封装了 REST 接口，只能拿到实体的 `entity_id` 与状态，
/// 拿不到设备注册表。这里直接走 HA 的 WebSocket API 拉取四份数据：
///
///   - `config/device_registry/list` 设备（“阳台植物灯” 这类，含 name / model / area_id）
///   - `config/entity_registry/list` 实体（含 `device_id` 外键）
///   - `config/area_registry/list`   区域（“金科1204 厨房” 这类，`area_id` → 中文名）
///   - `get_states`                  实时状态与 HA 算好的 `friendly_name`
///
/// 再按 `entity.device_id == device.id` 关联，得到「设备 → 实体列表」；
/// 按 `device.area_id == area.area_id` 关联，得到「设备 → 所在位置」。
/// 依赖 dart:io 的 WebSocket，适用于 Windows / Android / iOS，不支持 Web 平台。
class HomeAssistantRegistry {
  HomeAssistantRegistry({
    required this.baseUrl,
    required this.bearerToken,
    this.timeout = const Duration(seconds: 15),
  });

  /// 形如 `http://localhost:8123` 或 `http://192.168.51.82:8123`。
  final String baseUrl;

  /// 长期访问令牌。
  final String bearerToken;

  /// 单次连接与请求的超时时间。
  final Duration timeout;

  /// 连接 → 认证 → 拉取四份数据 → 关联 → 断开。
  Future<HaRegistry> load() async {
    final socket = await WebSocket.connect(
      '${baseUrl.replaceFirst('http', 'ws')}/api/websocket',
    ).timeout(timeout);

    final pending = <int, Completer<Object?>>{};
    var nextId = 1;
    final authed = Completer<void>();

    final subscription = socket.listen(
      (Object? raw) {
        final message = jsonDecode(raw! as String) as Map<String, dynamic>;
        switch (message['type']) {
          case 'auth_required':
            socket.add(
              jsonEncode({'type': 'auth', 'access_token': bearerToken}),
            );
          case 'auth_ok':
            authed.complete();
          case 'auth_invalid':
            authed.completeError(
              StateError('认证失败：${message['message'] ?? message}'),
            );
          case 'result':
            final completer = pending.remove(message['id']);
            if (completer == null) return;
            if (message['success'] == true) {
              completer.complete(message['result']);
            } else {
              completer.completeError(
                StateError('请求失败：${message['error'] ?? message}'),
              );
            }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!authed.isCompleted) authed.completeError(error, stackTrace);
      },
      onDone: () {
        if (!authed.isCompleted) {
          authed.completeError(StateError('WebSocket 在认证完成前被关闭'));
        }
      },
    );

    Future<List<dynamic>> request(String type) {
      final id = nextId++;
      final completer = Completer<Object?>();
      pending[id] = completer;
      socket.add(jsonEncode({'id': id, 'type': type}));
      return completer.future
          .timeout(timeout)
          .then((result) => (result as List<dynamic>?) ?? const <dynamic>[]);
    }

    try {
      await authed.future.timeout(timeout);
      final devices = await request('config/device_registry/list');
      final entities = await request('config/entity_registry/list');
      final areas = await request('config/area_registry/list');
      final states = await request('get_states');
      return _join(devices, entities, areas, states);
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  HaRegistry _join(
    List<dynamic> devicesRaw,
    List<dynamic> entitiesRaw,
    List<dynamic> areasRaw,
    List<dynamic> statesRaw,
  ) {
    final stateByEntityId = <String, Map<String, dynamic>>{
      for (final state in statesRaw)
        (state as Map<String, dynamic>)['entity_id'] as String: state,
    };

    // area_id → 区域中文名。注意不能从 area_id 反推名字：
    // slug 会吃掉空格（金科1204 阳台 → jin_ke_1204_yang_tai），且区域改名后 id 不变。
    final areaNameById = <String, String>{
      for (final area in areasRaw)
        (area as Map<String, dynamic>)['area_id'] as String:
            (area['name'] ?? '').toString(),
    };

    final deviceById = <String, Map<String, dynamic>>{
      for (final device in devicesRaw)
        (device as Map<String, dynamic>)['id'] as String: device,
    };

    final entitiesByDevice = <String, List<HaEntity>>{};
    final standalone = <HaEntity>[];

    for (final raw in entitiesRaw) {
      final entity = raw as Map<String, dynamic>;
      // 与 HA 前端保持一致：不展示被禁用的实体
      if (entity['disabled_by'] != null) continue;
      final entityId = entity['entity_id'] as String?;
      if (entityId == null) continue;

      final deviceId = entity['device_id'] as String?;
      final device = deviceId == null ? null : deviceById[deviceId];
      final state = stateByEntityId[entityId];

      final parsed = HaEntity(
        entityId: entityId,
        name: _entityName(entity, device, state),
        domain: entityId.split('.').first,
        deviceId: deviceId,
        state: state?['state'] as String?,
        attributes:
            (state?['attributes'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      );

      if (device == null) {
        standalone.add(parsed);
      } else {
        (entitiesByDevice[deviceId!] ??= <HaEntity>[]).add(parsed);
      }
    }

    final devices = deviceById.entries.map((entry) {
      final device = entry.value;
      final list = List<HaEntity>.of(entitiesByDevice[entry.key] ?? const [])
        ..sort((a, b) => a.name.compareTo(b.name));
      final areaId = device['area_id'] as String?;
      return HaDevice(
        id: entry.key,
        name: (device['name_by_user'] ?? device['name'] ?? entry.key)
            .toString(),
        manufacturer: device['manufacturer'] as String?,
        model: device['model'] as String?,
        areaId: areaId,
        areaName: areaId == null ? null : areaNameById[areaId],
        identifiers: _identifiers(device),
        entities: list,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    standalone.sort((a, b) => a.name.compareTo(b.name));

    return HaRegistry(devices: devices, standaloneEntities: standalone);
  }

  /// 复刻 HA 的命名规则，优先用前端已经算好的 `friendly_name`。
  String _entityName(
    Map<String, dynamic> entity,
    Map<String, dynamic>? device,
    Map<String, dynamic>? state,
  ) {
    final attributes = state?['attributes'];
    final friendly = attributes is Map ? attributes['friendly_name'] : null;
    if (friendly is String && friendly.trim().isNotEmpty) {
      return friendly.trim();
    }

    // 用户在 UI 里改过的实体名
    final renamed = entity['name'];
    if (renamed is String && renamed.trim().isNotEmpty) {
      return renamed.trim();
    }

    final original = (entity['original_name'] as String? ?? '').trim();
    if (entity['has_entity_name'] == true && device != null) {
      final deviceName = (device['name_by_user'] ?? device['name'] ?? '')
          .toString()
          .trim();
      return '$deviceName $original'.trim();
    }
    return original.isEmpty ? entity['entity_id'] as String : original;
  }

  List<String> _identifiers(Map<String, dynamic> device) {
    final raw = device['identifiers'] as List<dynamic>? ?? const [];
    return raw.map((pair) => (pair as List<dynamic>).join('/')).toList();
  }
}

/// 一条 Home Assistant 实体。
class HaEntity {
  const HaEntity({
    required this.entityId,
    required this.name,
    required this.domain,
    this.deviceId,
    this.state,
    this.attributes = const <String, dynamic>{},
  });

  final String entityId;

  /// 展示名，等价于 HA 界面 / REST 里的 `friendly_name`。
  final String name;

  /// 实体域：switch / button / light … 即 `entityId` 里 `.` 前的部分。
  final String domain;

  /// 归属设备的 id（设备注册表外键）。
  final String? deviceId;

  /// 当前状态；`button` 域没有 on/off，值是最后一次按下的时间戳。
  final String? state;

  final Map<String, dynamic> attributes;

  @override
  String toString() => 'HaEntity($entityId, name: $name, state: $state)';
}

/// 一台 Home Assistant 设备，及其名下的全部实体。
class HaDevice {
  const HaDevice({
    required this.id,
    required this.name,
    required this.entities,
    this.manufacturer,
    this.model,
    this.areaId,
    this.areaName,
    this.identifiers = const <String>[],
  });

  final String id;
  final String name;
  final String? manufacturer;
  final String? model;

  /// 区域 id，形如 `jin_ke_1204_chu_fang`。
  final String? areaId;

  /// 区域展示名，形如 `金科1204 厨房`；设备未归属区域时为 null。
  final String? areaName;

  /// 形如 `xiaomi_home/cn_783193359`，是设备在集成侧的原始唯一标识。
  final List<String> identifiers;

  final List<HaEntity> entities;

  /// 按实体域过滤，例如 `entitiesOfDomain('switch')`。
  List<HaEntity> entitiesOfDomain(String domain) =>
      entities.where((entity) => entity.domain == domain).toList();

  @override
  String toString() => 'HaDevice($name, ${entities.length} entities)';
}

/// 一次拉取得到的完整注册表快照。
class HaRegistry {
  const HaRegistry({required this.devices, required this.standaloneEntities});

  final List<HaDevice> devices;

  /// 没有归属设备的实体（较少见）。
  final List<HaEntity> standaloneEntities;

  /// 按设备名模糊匹配，例如 `findDevices('阳台植物灯')`。
  List<HaDevice> findDevices(String keyword) {
    final key = keyword.trim().toLowerCase();
    return devices
        .where((device) => device.name.toLowerCase().contains(key))
        .toList();
  }

  /// 某个位置下的所有设备，例如 `devicesInArea('金科1204 厨房')`。
  List<HaDevice> devicesInArea(String areaName) {
    final key = areaName.trim().toLowerCase();
    return devices
        .where((device) => (device.areaName ?? '').toLowerCase().contains(key))
        .toList();
  }

  /// 出现过的所有位置名（去重、按名排序）。
  List<String> get areaNames {
    final names = <String>{
      for (final device in devices)
        if (device.areaName != null) device.areaName!,
    }.toList();
    names.sort();
    return names;
  }

  /// 所有设备下的实体 + 未归属实体。
  List<HaEntity> get allEntities => [
    for (final device in devices) ...device.entities,
    ...standaloneEntities,
  ];
}

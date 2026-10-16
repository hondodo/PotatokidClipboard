import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页数据仓库实现：通过 WebSocket 客户端访问 Home Assistant。
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({
    required this._client,
    required this._log,
  });

  final HaWsClient _client;
  final LogService _log;

  @override
  Future<List<HaEntityStateModel>> fetchStates() async {
    final Map<String, dynamic> msg = await _client.request('get_states');
    final Object? result = msg['result'];
    if (result is! List) throw const HaDataException('get_states 返回结构异常');
    return result
        .whereType<Map>()
        .map((e) => HaEntityStateModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<HaRegistry> fetchRegistry() async {
    try {
      final Map<String, dynamic> areasMsg =
          await _client.request('config/area_registry/list');
      final Map<String, dynamic> devicesMsg =
          await _client.request('config/device_registry/list');
      final Map<String, dynamic> entriesMsg =
          await _client.request('config/entity_registry/list');
      final Map<String, HaDevice> devices =
          _parseDevices(devicesMsg['result']);
      return HaRegistry(
        areas: _parseAreas(areasMsg['result']),
        devices: devices,
        areaIdByEntity:
            _parseEntityAreaIds(entriesMsg['result'], devices),
      );
    } catch (e) {
      _log.warn('注册表拉取失败，房间分组降级为空：$e');
      return HaRegistry.empty;
    }
  }

  List<HaArea> _parseAreas(Object? result) {
    if (result is! List) throw const HaDataException('area_registry 结构异常');
    final List<(int, HaArea)> parsed = <(int, HaArea)>[];
    for (int i = 0; i < result.length; i++) {
      final dynamic raw = result[i];
      if (raw is! Map) continue;
      final String areaId = '${raw['area_id'] ?? ''}';
      if (areaId.isEmpty) continue;
      parsed.add((
        i,
        HaArea(
          areaId: areaId,
          name: '${raw['name'] ?? areaId}',
          position: (raw['position'] as num?)?.toInt() ?? 0,
        ),
      ));
    }
    // 按 HA 前端的自定义顺序（position）展示；无 position 时保持注册表原始顺序
    parsed.sort(((int, HaArea) a, (int, HaArea) b) {
      final int byPosition = a.$2.position.compareTo(b.$2.position);
      return byPosition != 0 ? byPosition : a.$1.compareTo(b.$1);
    });
    return parsed.map(((int, HaArea) e) => e.$2).toList(growable: false);
  }

  Map<String, HaDevice> _parseDevices(Object? result) {
    if (result is! List) throw const HaDataException('device_registry 结构异常');
    final Map<String, HaDevice> devices = <String, HaDevice>{};
    for (final dynamic raw in result) {
      if (raw is! Map) continue;
      final String id = '${raw['id'] ?? ''}';
      if (id.isEmpty) continue;
      final dynamic userName = raw['name_by_user'];
      final dynamic areaId = raw['area_id'];
      devices[id] = HaDevice(
        id: id,
        name: userName is String && userName.isNotEmpty
            ? userName
            : '${raw['name'] ?? id}',
        areaId: areaId is String && areaId.isNotEmpty ? areaId : null,
      );
    }
    return devices;
  }

  Map<String, String> _parseEntityAreaIds(
    Object? result,
    Map<String, HaDevice> devices,
  ) {
    if (result is! List) {
      throw const HaDataException('entity_registry 结构异常');
    }
    final Map<String, String> areaByEntity = <String, String>{};
    for (final dynamic raw in result) {
      if (raw is! Map) continue;
      final dynamic entityId = raw['entity_id'];
      if (entityId is! String || entityId.isEmpty) continue;
      final dynamic ownArea = raw['area_id'];
      String? areaId;
      if (ownArea is String && ownArea.isNotEmpty) {
        areaId = ownArea;
      } else {
        final dynamic deviceId = raw['device_id'];
        if (deviceId is String) areaId = devices[deviceId]?.areaId;
      }
      if (areaId != null && areaId.isNotEmpty) {
        areaByEntity[entityId] = areaId;
      }
    }
    return areaByEntity;
  }

  @override
  Stream<HaEntityStateModel> watchStateChanges() async* {
    await for (final Map<String, dynamic> raw in _client.stateChanged) {
      try {
        yield HaEntityStateModel.fromJson(raw);
      } catch (e) {
        _log.warn('state_changed 解析失败：$e');
      }
    }
  }

  @override
  Future<void> setEntityPower({
    required String entityId,
    required bool turnOn,
  }) {
    final String domain = entityId.split('.').first;
    return _client.callService(
      domain: domain,
      service: turnOn ? 'turn_on' : 'turn_off',
      entityId: entityId,
    );
  }
}

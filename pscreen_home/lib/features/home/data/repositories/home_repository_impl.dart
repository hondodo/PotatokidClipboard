import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/water_usage_record.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页数据仓库实现：通过 WebSocket 客户端访问 Home Assistant。
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({required this.client, required this.log});

  final HaWsClient client;
  final LogService log;

  @override
  Future<List<HaEntityStateModel>> fetchStates() async {
    final Map<String, dynamic> msg = await client.request('get_states');
    final Object? result = msg['result'];
    if (result is! List) throw const HaDataException('get_states 返回结构异常');
    return result.whereType<Map>().map((e) => HaEntityStateModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<HaRegistry> fetchRegistry() async {
    try {
      final Map<String, dynamic> areasMsg = await client.request('config/area_registry/list');
      final Map<String, dynamic> devicesMsg = await client.request('config/device_registry/list');
      final Map<String, dynamic> entriesMsg = await client.request('config/entity_registry/list');
      final Map<String, HaDevice> devices = _parseDevices(devicesMsg['result']);
      final (Map<String, String>, Map<String, String>) links = _parseEntityLinks(entriesMsg['result'], devices);
      return HaRegistry(
        areas: _parseAreas(areasMsg['result']),
        devices: devices,
        areaIdByEntity: links.$1,
        deviceIdByEntity: links.$2,
      );
    } catch (e) {
      log.warn('注册表拉取失败，房间分组降级为空：$e');
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
        HaArea(areaId: areaId, name: '${raw['name'] ?? areaId}', position: (raw['position'] as num?)?.toInt() ?? 0),
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
        name: userName is String && userName.isNotEmpty ? userName : '${raw['name'] ?? id}',
        areaId: areaId is String && areaId.isNotEmpty ? areaId : null,
      );
    }
    return devices;
  }

  /// 解析实体注册表：返回 (实体→房间, 实体→设备) 两个映射。
  ///
  /// 房间归属规则：实体自身 area_id 优先，缺失时回退到所属设备的 area_id；
  /// 设备归属直接取实体注册表的 device_id（合并同设备实体的关键数据）。
  (Map<String, String>, Map<String, String>) _parseEntityLinks(Object? result, Map<String, HaDevice> devices) {
    if (result is! List) {
      throw const HaDataException('entity_registry 结构异常');
    }
    final Map<String, String> areaByEntity = <String, String>{};
    final Map<String, String> deviceByEntity = <String, String>{};
    for (final dynamic raw in result) {
      if (raw is! Map) continue;
      final dynamic entityId = raw['entity_id'];
      if (entityId is! String || entityId.isEmpty) continue;
      final dynamic rawDeviceId = raw['device_id'];
      final String? deviceId = rawDeviceId is String && rawDeviceId.isNotEmpty ? rawDeviceId : null;
      if (deviceId != null) deviceByEntity[entityId] = deviceId;
      final dynamic ownArea = raw['area_id'];
      String? areaId;
      if (ownArea is String && ownArea.isNotEmpty) {
        areaId = ownArea;
      } else if (deviceId != null) {
        areaId = devices[deviceId]?.areaId;
      }
      if (areaId != null && areaId.isNotEmpty) {
        areaByEntity[entityId] = areaId;
      }
    }
    return (areaByEntity, deviceByEntity);
  }

  @override
  Stream<HaEntityStateModel> watchStateChanges() async* {
    await for (final Map<String, dynamic> raw in client.stateChanged) {
      try {
        yield HaEntityStateModel.fromJson(raw);
      } catch (e) {
        log.warn('state_changed 解析失败：$e');
      }
    }
  }

  @override
  Future<void> setEntityPower({required String entityId, required bool turnOn}) {
    final String domain = entityId.split('.').first;
    return client.callService(domain: domain, service: turnOn ? 'turn_on' : 'turn_off', entityId: entityId);
  }

  @override
  Future<void> setLightBrightness({required String entityId, required int percent}) {
    final int brightness = (percent.clamp(1, 100) * 255 / 100).round();
    return client.callService(
      domain: 'light',
      service: 'turn_on',
      entityId: entityId,
      serviceData: <String, dynamic>{'brightness': brightness},
    );
  }

  @override
  Future<void> setLightColorTemperature({required String entityId, required int kelvin}) {
    return client.callService(
      domain: 'light',
      service: 'turn_on',
      entityId: entityId,
      serviceData: <String, dynamic>{'color_temp_kelvin': kelvin},
    );
  }

  @override
  Future<void> setLightEffect({required String entityId, required String effect}) {
    return client.callService(
      domain: 'light',
      service: 'turn_on',
      entityId: entityId,
      serviceData: <String, dynamic>{'effect': effect},
    );
  }

  @override
  Future<void> setClimateTemperature({required String entityId, required double temperature}) {
    return client.callService(
      domain: 'climate',
      service: 'set_temperature',
      entityId: entityId,
      serviceData: <String, dynamic>{'temperature': temperature},
    );
  }

  @override
  Future<void> setClimateHvacMode({required String entityId, required String mode}) {
    return client.callService(
      domain: 'climate',
      service: 'set_hvac_mode',
      entityId: entityId,
      serviceData: <String, dynamic>{'hvac_mode': mode},
    );
  }

  @override
  Future<void> setClimateFanMode({required String entityId, required String mode}) {
    return client.callService(
      domain: 'climate',
      service: 'set_fan_mode',
      entityId: entityId,
      serviceData: <String, dynamic>{'fan_mode': mode},
    );
  }

  @override
  Future<void> setClimateSwingMode({required String entityId, required String mode}) {
    return client.callService(
      domain: 'climate',
      service: 'set_swing_mode',
      entityId: entityId,
      serviceData: <String, dynamic>{'swing_mode': mode},
    );
  }

  @override
  Future<void> setFanPresetMode({required String entityId, required String mode}) {
    return client.callService(
      domain: 'fan',
      service: 'set_preset_mode',
      entityId: entityId,
      serviceData: <String, dynamic>{'preset_mode': mode},
    );
  }

  @override
  Future<void> setFanPercentage({required String entityId, required int percentage}) {
    return client.callService(
      domain: 'fan',
      service: 'set_percentage',
      entityId: entityId,
      serviceData: <String, dynamic>{'percentage': percentage.clamp(0, 100)},
    );
  }

  @override
  Future<void> setFanOscillating({required String entityId, required bool oscillating}) {
    return client.callService(
      domain: 'fan',
      service: 'oscillate',
      entityId: entityId,
      serviceData: <String, dynamic>{'oscillating': oscillating},
    );
  }

  @override
  Future<void> pressButton({required String entityId}) {
    return client.callService(domain: 'button', service: 'press', entityId: entityId);
  }

  @override
  Future<void> selectOption({required String entityId, required String option}) {
    return client.callService(
      domain: 'select',
      service: 'select_option',
      entityId: entityId,
      serviceData: <String, dynamic>{'option': option},
    );
  }

  @override
  Future<void> setWaterHeaterTemperature({required String entityId, required double temperature}) {
    return client.callService(
      domain: 'water_heater',
      service: 'set_temperature',
      entityId: entityId,
      serviceData: <String, dynamic>{'temperature': temperature},
    );
  }

  @override
  Future<void> setWaterHeaterOperationMode({required String entityId, required String mode}) {
    return client.callService(
      domain: 'water_heater',
      service: 'set_operation_mode',
      entityId: entityId,
      serviceData: <String, dynamic>{'operation_mode': mode},
    );
  }

  @override
  Future<List<WaterUsageRecord>> fetchWaterUsageRecords({
    required String entityId,
    required DateTime start,
    required DateTime end,
  }) async {
    final Map<String, dynamic> msg = await client.request('history/history_during_period', <String, dynamic>{
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'entity_ids': <String>[entityId],
      'minimal_response': false,
      'no_attributes': false,
      'significant_changes_only': false,
    });
    final Object? result = msg['result'];
    if (result is! Map) return const <WaterUsageRecord>[];
    final Object? rawList = result[entityId];
    if (rawList is! List) return const <WaterUsageRecord>[];
    return rawList
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => WaterUsageRecord.fromHistoryItem(Map<String, dynamic>.from(item)))
        .whereType<WaterUsageRecord>()
        .toList(growable: false);
  }

  @override
  Future<void> setTextValue({required String entityId, required String value}) {
    return client.callService(
      domain: 'text',
      service: 'set_value',
      entityId: entityId,
      serviceData: <String, dynamic>{'value': value},
    );
  }

  @override
  Future<void> setNumberValue({required String entityId, required double value}) {
    return client.callService(
      domain: 'number',
      service: 'set_value',
      entityId: entityId,
      serviceData: <String, dynamic>{'value': value},
    );
  }

  @override
  Future<void> pressNotifyAction({required String entityId, required String message}) {
    return client.callService(
      domain: 'notify',
      service: 'send_message',
      entityId: entityId,
      serviceData: <String, dynamic>{'message': message},
    );
  }
}

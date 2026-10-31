import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 冰箱摘要：冷藏 / 冷冻 / 变温三舱温度 + 模式 + 故障/门提醒。
///
/// 米家冰箱在 HA 里没有总电源，只有 mode select、各舱 target number
/// 和当前温度 sensor；食材管理是云端数据，HA 未暴露。
class FridgeSummary {
  const FridgeSummary({
    required this.deviceId,
    required this.name,
    required this.mode,
    required this.modes,
    required this.zones,
    this.modeEntityId,
    this.fault,
    this.doorWarning = false,
    this.environmentTemperature,
    this.environmentHumidity,
    this.refrigeratorOpenTimes,
    this.freezerOpenTimes,
    this.totalRuntimeMinutes,
  });

  static FridgeSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? mode =
        _byId(entities, '_mode_p_2_2', domain: 'select');
    if (mode == null) return null;

    final List<FridgeZone> zones = <FridgeZone?>[
      _zone(
        entities,
        name: '冷藏室',
        currentId: '_temperature_p_3_1',
        targetId: '_target_temperature_p_3_2',
      ),
      _zone(
        entities,
        name: '冷冻室',
        currentId: '_temperature_p_4_1',
        targetId: '_target_temperature_p_4_2',
      ),
      _zone(
        entities,
        name: '变温舱',
        currentId: '_temperature_p_6_1',
        targetId: '_target_temperature_p_6_2',
      ),
    ].whereType<FridgeZone>().toList(growable: false);
    if (zones.isEmpty) return null;

    final HaEntityStateModel? fault =
        _byId(entities, '_fault_p_2_1', domain: 'sensor');
    final HaEntityStateModel? door =
        _byId(entities, '_door_not_close_remind_p_2_3', domain: 'sensor');

    return FridgeSummary(
      deviceId: deviceId,
      name: name,
      mode: mode.state,
      modes: mode.options,
      modeEntityId: mode.entityId,
      zones: zones,
      fault: fault?.state,
      doorWarning: door?.state == '1',
      environmentTemperature:
          _int(_byId(entities, '_environment_temp_p_10_9', domain: 'sensor')
              ?.state),
      environmentHumidity:
          _int(_byId(entities, '_environment_humidity_p_10_10',
                  domain: 'sensor')
              ?.state),
      refrigeratorOpenTimes:
          _int(_byId(entities, '_ref_open_times_p_10_38', domain: 'sensor')
              ?.state),
      freezerOpenTimes:
          _int(_byId(entities, '_frz_open_times_p_10_40', domain: 'sensor')
              ?.state),
      totalRuntimeMinutes:
          _int(_byId(entities, '_total_runtime_p_10_23', domain: 'sensor')
              ?.state),
    );
  }

  final String deviceId;
  final String name;
  final String mode;
  final List<String> modes;
  final List<FridgeZone> zones;
  final String? modeEntityId;
  final String? fault;
  final bool doorWarning;
  final int? environmentTemperature;
  final int? environmentHumidity;
  final int? refrigeratorOpenTimes;
  final int? freezerOpenTimes;
  final int? totalRuntimeMinutes;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '0' && value != 'unknown' && value.isNotEmpty;
  }

  bool get hasWarning => hasFault || doorWarning;

  String get statusLabel {
    if (hasFault) return '故障';
    if (doorWarning) return '有门未关';
    return '$mode模式';
  }

  String get runtimeLabel {
    final int? minutes = totalRuntimeMinutes;
    if (minutes == null) return '—';
    if (minutes < 60) return '$minutes 分钟';
    final int days = minutes ~/ (60 * 24);
    final int hours = (minutes % (60 * 24)) ~/ 60;
    if (days > 0) return '$days 天 $hours 小时';
    return '$hours 小时';
  }

  static FridgeZone? _zone(
    Iterable<HaEntityStateModel> entities, {
    required String name,
    required String currentId,
    required String targetId,
  }) {
    final HaEntityStateModel? target =
        _byId(entities, targetId, domain: 'number');
    if (target == null) return null;
    final HaEntityStateModel? current =
        _byId(entities, currentId, domain: 'sensor');
    return FridgeZone(
      name: name,
      currentTemperature: _int(current?.state),
      targetTemperature: _int(target.state) ?? 0,
      minTemperature: _int(target.attributes['min']) ?? 0,
      maxTemperature: _int(target.attributes['max']) ?? 0,
      currentEntityId: current?.entityId,
      targetEntityId: target.entityId,
    );
  }

  static HaEntityStateModel? _byId(
    Iterable<HaEntityStateModel> entities,
    String part, {
    required String domain,
  }) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != domain) continue;
      if (entity.entityId.contains(part)) return entity;
    }
    return null;
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}

class FridgeZone {
  const FridgeZone({
    required this.name,
    required this.currentTemperature,
    required this.targetTemperature,
    required this.minTemperature,
    required this.maxTemperature,
    this.currentEntityId,
    required this.targetEntityId,
  });

  final String name;
  final int? currentTemperature;
  final int targetTemperature;
  final int minTemperature;
  final int maxTemperature;
  final String? currentEntityId;
  final String targetEntityId;
}

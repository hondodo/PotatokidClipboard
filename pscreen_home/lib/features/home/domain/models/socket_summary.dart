import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';

/// 智能插座摘要：开关 + 当前功率 / 累计电量 / 设备温度 / 开关次数。
class SocketSummary {
  const SocketSummary({
    required this.deviceId,
    required this.name,
    required this.isOn,
    required this.powerEntityId,
    required this.stats,
    this.fault,
  });

  static SocketSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? power =
        _byId(entities, '_on_p_2_1', domain: 'switch');
    if (power == null) return null;
    final PowerStats? stats = PowerStats.tryBuild(entities);
    if (stats == null || stats.currentWatts == null) return null;

    return SocketSummary(
      deviceId: deviceId,
      name: name,
      isOn: power.isOn,
      powerEntityId: power.entityId,
      stats: stats,
      fault: _byId(entities, '_fault_p_2_3', domain: 'sensor')?.state,
    );
  }

  final String deviceId;
  final String name;
  final bool isOn;
  final String powerEntityId;
  final PowerStats stats;
  final String? fault;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '无故障' &&
        value != 'No Faults' &&
        value != 'unknown' &&
        value.isNotEmpty;
  }

  String get statusLabel => hasFault ? '故障' : (isOn ? '已开启' : '已关闭');

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
}

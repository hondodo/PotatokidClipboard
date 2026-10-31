import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 设备用电信息：当前功率、累计用电、设备温度、开关次数、空调外机功率。
///
/// 智能插座通常有 `_electric_power_p_11_2` + `_power_consumption_p_11_1`；
/// 空调插座的当前功率是 `_electric_power_p_5_1`，没有累计电量。
/// 空调外机功率（电压 × 电流）使用 `_ac_power_`，与插座功率区分。
class PowerStats {
  const PowerStats({
    this.currentWatts,
    this.totalKwh,
    this.deviceTemperature,
    this.switchCount,
    this.acPowerWatts,
    this.currentEntityId,
    this.totalEntityId,
    this.temperatureEntityId,
    this.countEntityId,
    this.acPowerEntityId,
  });

  static PowerStats? tryBuild(Iterable<HaEntityStateModel> entities) {
    final HaEntityStateModel? current =
        _byId(entities, '_electric_power_', domain: 'sensor');
    final HaEntityStateModel? total =
        _byId(entities, '_power_consumption_', domain: 'sensor');
    final HaEntityStateModel? temperature =
        _byId(entities, '_temperature_p_12_2', domain: 'sensor');
    final HaEntityStateModel? count =
        _byId(entities, '_on_off_count_p_12_1', domain: 'sensor');
    final HaEntityStateModel? acPower =
        _byId(entities, '_ac_power_', domain: 'sensor');
    if (current == null &&
        total == null &&
        temperature == null &&
        count == null &&
        acPower == null) {
      return null;
    }

    return PowerStats(
      currentWatts: _double(current?.state),
      totalKwh: _double(total?.state),
      deviceTemperature: _int(temperature?.state),
      switchCount: _int(count?.state),
      acPowerWatts: _double(acPower?.state),
      currentEntityId: current?.entityId,
      totalEntityId: total?.entityId,
      temperatureEntityId: temperature?.entityId,
      countEntityId: count?.entityId,
      acPowerEntityId: acPower?.entityId,
    );
  }

  final double? currentWatts;
  final double? totalKwh;
  final int? deviceTemperature;
  final int? switchCount;
  final double? acPowerWatts;
  final String? currentEntityId;
  final String? totalEntityId;
  final String? temperatureEntityId;
  final String? countEntityId;
  final String? acPowerEntityId;

  bool get hasData =>
      currentWatts != null ||
      totalKwh != null ||
      deviceTemperature != null ||
      switchCount != null ||
      acPowerWatts != null;

  String get currentPowerLabel {
    final double? value = acPowerWatts ?? currentWatts;
    if (value == null) return '—';
    if (value <= 0) return '0 W';
    if (value < 0.1) return '<0.1 W';
    if (value < 10) return '${value.toStringAsFixed(1)} W';
    return '${value.round()} W';
  }

  String get totalLabel {
    final double? value = totalKwh;
    if (value == null) return '—';
    return '${value.toStringAsFixed(2)} kWh';
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

  static double? _double(String? raw) =>
      raw == null ? null : double.tryParse(raw);

  static int? _int(String? raw) => raw == null ? null : int.tryParse(raw);
}

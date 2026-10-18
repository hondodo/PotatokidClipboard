import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 空气炸锅摘要：模式、温度、时间、剩余时间、开始/暂停/继续/停止。
class AirFryerSummary {
  const AirFryerSummary({
    required this.deviceId,
    required this.name,
    required this.status,
    required this.temperature,
    required this.minutes,
    required this.modes,
    required this.mode,
    this.fault,
    this.remainingMinutes,
    this.minTemperature = 40,
    this.maxTemperature = 230,
    this.temperatureStep = 5,
    this.minMinutes = 1,
    this.maxMinutes = 1440,
    this.modeEntityId,
    this.temperatureEntityId,
    this.timeEntityId,
    this.startEntityId,
    this.pauseEntityId,
    this.resumeEntityId,
    this.stopEntityId,
    this.autoKeepWarmEntityId,
    this.currentKeepWarmEntityId,
    this.autoKeepWarm = false,
    this.currentKeepWarm = false,
  });

  static AirFryerSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? mode =
        _byId(entities, '_mode_p_2_25', domain: 'select');
    final HaEntityStateModel? temperature =
        _byId(entities, '_target_temperature_p_2_7', domain: 'number');
    final HaEntityStateModel? time =
        _byId(entities, '_target_time_p_2_5', domain: 'number');
    if (mode == null || temperature == null || time == null) return null;

    final HaEntityStateModel? autoKeepWarm =
        _byId(entities, '_auto_keep_warm_p_2_23', domain: 'switch');
    final HaEntityStateModel? currentKeepWarm =
        _byId(entities, '_current_keep_warm_p_2_24', domain: 'switch');

    return AirFryerSummary(
      deviceId: deviceId,
      name: name,
      status: _byId(entities, '_status_p_2_2', domain: 'sensor')?.state ??
          '待机中',
      temperature: _int(temperature.state) ?? 80,
      minutes: _int(time.state) ?? 8,
      modes: mode.options,
      mode: mode.state,
      fault: _byId(entities, '_fault_p_2_3', domain: 'sensor')?.state,
      remainingMinutes:
          _int(_byId(entities, '_left_time_p_2_22', domain: 'sensor')?.state),
      minTemperature: _int(temperature.attributes['min']) ?? 40,
      maxTemperature: _int(temperature.attributes['max']) ?? 230,
      temperatureStep: _int(temperature.attributes['step']) ?? 5,
      minMinutes: _int(time.attributes['min']) ?? 1,
      maxMinutes: _int(time.attributes['max']) ?? 1440,
      modeEntityId: mode.entityId,
      temperatureEntityId: temperature.entityId,
      timeEntityId: time.entityId,
      startEntityId:
          _byId(entities, '_start_cook_a_2_1', domain: 'button')?.entityId,
      pauseEntityId: _byId(entities, '_pause_a_2_7', domain: 'button')?.entityId,
      resumeEntityId:
          _byId(entities, '_resume_cook_a_2_8', domain: 'button')?.entityId,
      stopEntityId:
          _byId(entities, '_cancel_cooking_a_2_6', domain: 'button')?.entityId,
      autoKeepWarmEntityId: autoKeepWarm?.entityId,
      currentKeepWarmEntityId: currentKeepWarm?.entityId,
      autoKeepWarm: autoKeepWarm?.isOn ?? false,
      currentKeepWarm: currentKeepWarm?.isOn ?? false,
    );
  }

  final String deviceId;
  final String name;
  final String status;
  final int temperature;
  final int minutes;
  final List<String> modes;
  final String mode;
  final String? fault;
  final int? remainingMinutes;
  final int minTemperature;
  final int maxTemperature;
  final int temperatureStep;
  final int minMinutes;
  final int maxMinutes;
  final String? modeEntityId;
  final String? temperatureEntityId;
  final String? timeEntityId;
  final String? startEntityId;
  final String? pauseEntityId;
  final String? resumeEntityId;
  final String? stopEntityId;
  final String? autoKeepWarmEntityId;
  final String? currentKeepWarmEntityId;
  final bool autoKeepWarm;
  final bool currentKeepWarm;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '无错误' &&
        value != 'No Faults' &&
        value != 'unknown' &&
        value.isNotEmpty;
  }

  bool get isActive {
    final String value = status;
    if (value.isEmpty ||
        value.contains('关机') ||
        value.contains('待机') ||
        value.contains('完成') ||
        value == '空闲') {
      return false;
    }
    return true;
  }

  String get statusLabel {
    if (hasFault) return '故障';
    final int? left = remainingMinutes;
    if (isActive && left != null && left > 0) {
      return '$status · 剩余 $left 分钟';
    }
    return status;
  }

  String get settingLabel => '$mode · $temperature°C · $minutes 分钟';

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

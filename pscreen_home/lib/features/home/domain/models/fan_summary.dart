import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 风扇摘要：fan 主实体 + 关机延时 number。
///
/// 米家风扇在 HA 里是一个 `fan.*` 实体（preset_mode / percentage /
/// oscillating），延时关闭是独立的 `number.*_off_delay_time_p_2_10`
/// （风扇灯是 `number.*_delay_time_p_6_2`）。全部按实体 id / 属性识别，
/// 不依赖 friendly_name。
class FanSummary {
  const FanSummary({
    required this.deviceId,
    required this.name,
    required this.entity,
    required this.modes,
    required this.mode,
    required this.percentage,
    required this.oscillating,
    this.percentageStep = 0,
    this.delayMinutes,
    this.delayEntityId,
    this.delayMaxMinutes = 480,
    this.supportsOscillation = true,
    this.masterSwitch,
  });

  static FanSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    HaEntityStateModel? fan;
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'fan') continue;
      fan = entity;
      break;
    }
    if (fan == null) return null;

    final HaEntityStateModel? delay =
        _byId(entities, '_off_delay_time_p_2_10', domain: 'number') ??
            _byId(entities, '_delay_time_p_6_2', domain: 'number');
    final HaEntityStateModel? masterSwitch =
        _byId(entities, '_all_on_p_10_1', domain: 'switch');
    final int? minutes = delay == null ? null : int.tryParse(delay.state);
    final int delayMax = _intAttr(delay?.attributes['max']) ?? 480;
    final List<String> modes = fan.presetModes;
    final String? preset = fan.presetMode;

    return FanSummary(
      deviceId: deviceId,
      name: name,
      entity: fan,
      modes: modes,
      mode: preset ?? (modes.isNotEmpty ? modes.first : ''),
      percentage: fan.fanPercentage ?? 0,
      oscillating: fan.isOscillating,
      percentageStep: _doubleAttr(fan.attributes['percentage_step']) ?? 0,
      delayMinutes: minutes,
      delayEntityId: delay?.entityId,
      delayMaxMinutes: delayMax,
      supportsOscillation: fan.attributes.containsKey('oscillating'),
      masterSwitch: masterSwitch,
    );
  }

  final String deviceId;
  final String name;
  final HaEntityStateModel entity;

  /// 预设模式（直吹风 / 睡眠风）
  final List<String> modes;
  final String mode;

  /// 0-100 档位百分比
  final int percentage;
  final bool oscillating;

  /// HA percentage_step：33.33 表示三挡，1 表示无级调速
  final double percentageStep;

  /// 关机延时（分钟，0 表示关闭）
  final int? delayMinutes;
  final String? delayEntityId;
  final int delayMaxMinutes;
  final bool supportsOscillation;

  /// 风扇灯的「总开关」（`switch.*_all_on_p_10_1`），普通风扇为 null
  final HaEntityStateModel? masterSwitch;

  bool get hasMasterSwitch => masterSwitch != null;

  String? get masterSwitchEntityId => masterSwitch?.entityId;

  bool get masterOn => masterSwitch?.isOn ?? isOn;

  bool get isOn => entity.isOn;

  bool get hasDelay => delayEntityId != null;

  /// 无级调速（风扇灯）还是固定三挡（普通风扇）
  bool get isContinuous => percentageStep > 0 && percentageStep <= 1;

  /// 1 / 2 / 3 档；0 表示没有档位信息（无级调速也返回 0）
  int get speedLevel {
    if (isContinuous || percentage <= 0) return 0;
    return (percentage * 3 / 100).ceil().clamp(1, 3).toInt();
  }

  String get speedLabel {
    if (isContinuous) return '$percentage';
    return switch (speedLevel) {
      1 => '一挡',
      2 => '二挡',
      3 => '三挡',
      _ => '关闭',
    };
  }

  String get statusLabel {
    if (!isOn) return '已关闭';
    return '$mode · $speedLabel';
  }

  String get delayLabel {
    final int value = delayMinutes ?? 0;
    if (value <= 0) return '关闭';
    final int hours = value ~/ 60;
    final int minutes = value % 60;
    if (hours == 0) return '$minutes分钟';
    if (minutes == 0) return '$hours小时';
    return '$hours小时$minutes分钟';
  }

  /// 1/2/3 档对应的 HA percentage
  static int percentageForLevel(int level) => switch (level) {
        1 => 33,
        2 => 66,
        _ => 100,
      };

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

  static int? _intAttr(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _doubleAttr(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

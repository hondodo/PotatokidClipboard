import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 抽油烟机摘要：电源、风量、灯光、延时关机、自动巡航、假日模式、干洗。
class RangeHoodSummary {
  const RangeHoodSummary({
    required this.deviceId,
    required this.name,
    required this.isOn,
    required this.fanLevels,
    required this.fanLevel,
    required this.lightOn,
    required this.delayOn,
    required this.delayMinutes,
    required this.cruiseOn,
    required this.holidayOn,
    this.fault,
    this.fanEntityId,
    this.powerEntityId,
    this.lightEntityId,
    this.delayEntityId,
    this.delayTimeEntityId,
    this.cruiseEntityId,
    this.holidayEntityId,
    this.dryCleaningStatus,
    this.dryCleaningStartEntityId,
    this.dryCleaningStopEntityId,
  });

  static RangeHoodSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? power =
        _byId(entities, '_on_p_2_1', domain: 'switch');
    final HaEntityStateModel? fan =
        _byId(entities, '_fan_level_p_10_2', domain: 'select');
    if (power == null || fan == null) return null;

    final HaEntityStateModel? light =
        _byId(entities, '_s_5_light', domain: 'light');
    final HaEntityStateModel? delay =
        _byId(entities, '_off_delay_p_2_5', domain: 'switch');
    final HaEntityStateModel? delayTime =
        _byId(entities, '_off_delay_time_p_2_4', domain: 'number');
    final HaEntityStateModel? cruise =
        _byId(entities, '_cruise_on_p_9_5', domain: 'switch');
    final HaEntityStateModel? holiday =
        _byId(entities, '_holiday_on_p_9_6', domain: 'switch');

    return RangeHoodSummary(
      deviceId: deviceId,
      name: name,
      isOn: power.isOn,
      fanLevels: fan.options,
      fanLevel: fan.state,
      lightOn: light?.isOn ?? false,
      delayOn: delay?.isOn ?? false,
      delayMinutes: _int(delayTime?.state) ?? 1,
      cruiseOn: cruise?.isOn ?? false,
      holidayOn: holiday?.isOn ?? false,
      fault: _byId(entities, '_fault_p_2_2', domain: 'sensor')?.state,
      fanEntityId: fan.entityId,
      powerEntityId: power.entityId,
      lightEntityId: light?.entityId,
      delayEntityId: delay?.entityId,
      delayTimeEntityId: delayTime?.entityId,
      cruiseEntityId: cruise?.entityId,
      holidayEntityId: holiday?.entityId,
      dryCleaningStatus:
          _byId(entities, '_dry_cleaning_status_p_11_2', domain: 'sensor')
              ?.state,
      dryCleaningStartEntityId:
          _byId(entities, '_execute_dry_cleaning_a_11_2', domain: 'button')
              ?.entityId,
      dryCleaningStopEntityId:
          _byId(entities, '_stop_dry_cleaning_a_11_1', domain: 'button')
              ?.entityId,
    );
  }

  final String deviceId;
  final String name;
  final bool isOn;
  final List<String> fanLevels;
  final String fanLevel;
  final bool lightOn;
  final bool delayOn;
  final int delayMinutes;
  final bool cruiseOn;
  final bool holidayOn;
  final String? fault;
  final String? fanEntityId;
  final String? powerEntityId;
  final String? lightEntityId;
  final String? delayEntityId;
  final String? delayTimeEntityId;
  final String? cruiseEntityId;
  final String? holidayEntityId;
  final String? dryCleaningStatus;
  final String? dryCleaningStartEntityId;
  final String? dryCleaningStopEntityId;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '0' && value != 'unknown' && value.isNotEmpty;
  }

  bool get isDryCleaning =>
      dryCleaningStatus != null &&
      dryCleaningStatus != '未启动' &&
      dryCleaningStatus != 'unknown';

  String get statusLabel => hasFault
      ? '故障'
      : (isOn ? fanLevel : '已关闭');

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

  static int? _int(String? raw) => raw == null ? null : int.tryParse(raw);
}

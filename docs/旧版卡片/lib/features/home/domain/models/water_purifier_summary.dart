import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 净水器摘要：TDS、进水温度、复合/RO 滤芯寿命、假期模式等。
class WaterPurifierSummary {
  const WaterPurifierSummary({
    required this.deviceId,
    required this.name,
    required this.status,
    required this.filters,
    this.tds,
    this.temperature,
    this.fault,
    this.holidayMode = false,
    this.pipelineConnected = false,
    this.alarmOn = false,
    this.holidayEntityId,
    this.pipelineEntityId,
    this.alarmEntityId,
    this.stopEntityId,
  });

  static WaterPurifierSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? status =
        _byId(entities, '_status_p_2_2', domain: 'sensor');
    final HaEntityStateModel? tds =
        _byId(entities, '_tds_out_p_4_2', domain: 'sensor');
    if (status == null || tds == null) return null;

    final HaEntityStateModel? ppcLife =
        _byId(entities, '_filter_life_level_p_3_1', domain: 'sensor');
    final HaEntityStateModel? roLife =
        _byId(entities, '_filter_life_level_p_5_1', domain: 'sensor');
    if (ppcLife == null && roLife == null) return null;

    final HaEntityStateModel? holiday =
        _byId(entities, '_holiday_mode_p_2_7', domain: 'switch');
    final HaEntityStateModel? pipeline =
        _byId(entities, '_pipeline_connection_p_2_5', domain: 'switch');
    final HaEntityStateModel? alarm =
        _byId(entities, '_alarm_p_9_1', domain: 'switch');

    return WaterPurifierSummary(
      deviceId: deviceId,
      name: name,
      status: status.state,
      tds: _int(tds.state),
      temperature:
          _int(_byId(entities, '_temperature_p_2_3', domain: 'sensor')?.state),
      fault: _byId(entities, '_fault_p_2_1', domain: 'sensor')?.state,
      filters: <WaterFilter>[
        if (ppcLife != null)
          WaterFilter(
            name: 'PPC复合滤芯',
            lifePercent: _int(ppcLife.state) ?? 0,
            leftDays: _int(
              _byId(entities, '_filter_left_time_p_3_2', domain: 'sensor')
                  ?.state,
            ),
          ),
        if (roLife != null)
          WaterFilter(
            name: 'RO反渗透滤芯',
            lifePercent: _int(roLife.state) ?? 0,
            leftDays: _int(
              _byId(entities, '_filter_left_time_p_5_2', domain: 'sensor')
                  ?.state,
            ),
          ),
      ],
      holidayMode: holiday?.isOn ?? false,
      pipelineConnected: pipeline?.isOn ?? false,
      alarmOn: alarm?.isOn ?? false,
      holidayEntityId: holiday?.entityId,
      pipelineEntityId: pipeline?.entityId,
      alarmEntityId: alarm?.entityId,
      stopEntityId:
          _byId(entities, '_stop_production_a_2_1', domain: 'button')?.entityId,
    );
  }

  final String deviceId;
  final String name;
  final String status;
  final int? tds;
  final int? temperature;
  final String? fault;
  final List<WaterFilter> filters;
  final bool holidayMode;
  final bool pipelineConnected;
  final bool alarmOn;
  final String? holidayEntityId;
  final String? pipelineEntityId;
  final String? alarmEntityId;
  final String? stopEntityId;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '0' && value != 'unknown' && value.isNotEmpty;
  }

  String get statusLabel => hasFault ? '故障' : status;

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

class WaterFilter {
  const WaterFilter({
    required this.name,
    required this.lifePercent,
    this.leftDays,
  });

  final String name;
  final int lifePercent;
  final int? leftDays;
}

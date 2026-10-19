import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 电热水瓶摘要：HA 把设备拆成 select / number / switch / sensor / notify /
/// button 等实体，这里按设备实体名/id 组装成可渲染的状态。
///
/// 只有「内置三种模式 + 参数控制」；米家的扩展/自定义模式定义在云端，
/// HA 只暴露 `text.*_mode_id`（如 M0），没有模式列表。
class KettleSummary {
  const KettleSummary({
    required this.deviceId,
    required this.name,
    required this.status,
    required this.temperature,
    required this.modes,
    required this.mode,
    required this.targetTemperature,
    required this.keepWarmTemperature,
    required this.keepWarmOn,
    required this.dechlorinationOn,
    required this.rapidCoolingOn,
    required this.childLocked,
    this.modeId,
    this.boilingPoint = 100,
    this.pureWaterKeepWarmTemperature = 66,
    this.tapWaterKeepWarmTemperature = 51,
    this.fault,
    this.modeEntityId,
    this.targetEntityId,
    this.keepWarmEntityId,
    this.keepWarmTempEntityId,
    this.dechlorinationEntityId,
    this.rapidCoolingEntityId,
    this.pureWaterTempEntityId,
    this.tapWaterTempEntityId,
    this.startEntityId,
    this.stopEntityId,
    this.lockMode,
  });

  static KettleSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? modeEntity = _find(
      entities,
      (HaEntityStateModel e) =>
          e.domain == 'select' && e.options.contains('自来水'),
    );
    final HaEntityStateModel? temperature =
        _find(entities, _idHas('_temperature_p_2_6'));
    final HaEntityStateModel? status =
        _find(entities, _idHas('_status_p_2_1'));
    if (modeEntity == null || temperature == null || status == null) {
      return null;
    }

    final HaEntityStateModel? target =
        _find(entities, _idHas('_target_temperature_p_2_5'));
    final HaEntityStateModel? keepWarmTemp =
        _find(entities, _idHas('_keep_warm_temperature_p_2_8'));
    final HaEntityStateModel? pureWaterTemp =
        _find(entities, _idHas('_keep_warm_temperature_p_2_13'));
    final HaEntityStateModel? tapWaterTemp =
        _find(entities, _idHas('_keep_warm_temperature_p_2_14'));
    final HaEntityStateModel? modeId =
        _find(entities, _idHas('_mode_id_p_2_17'));
    final HaEntityStateModel? boilingPoint =
        _find(entities, _idHas('_boiling_point_p_2_9'));
    final HaEntityStateModel? keepWarm =
        _find(entities, _idHas('_auto_keep_warm_p_2_7'));
    final HaEntityStateModel? dechlorination =
        _find(entities, _idHas('_dechlorination_p_2_10'));
    final HaEntityStateModel? rapidCooling =
        _find(entities, _idHas('_rapid_cooling_p_2_12'));
    final HaEntityStateModel? lockStatus =
        _find(entities, _idHas('_current_physical_control_lock_p_4_2'));
    final HaEntityStateModel? lockMode =
        _find(entities, _idHas('_mode_p_4_3'));

    return KettleSummary(
      deviceId: deviceId,
      name: name,
      status: status.state,
      temperature: double.tryParse(temperature.state) ?? 0,
      fault: _find(entities, _idHas('_fault_p_2_4'))?.state,
      modes: modeEntity.options,
      mode: modeEntity.state,
      targetTemperature: double.tryParse(target?.state ?? '') ?? 100,
      keepWarmTemperature: double.tryParse(keepWarmTemp?.state ?? '') ?? 55,
      pureWaterKeepWarmTemperature:
          double.tryParse(pureWaterTemp?.state ?? '') ?? 66,
      tapWaterKeepWarmTemperature:
          double.tryParse(tapWaterTemp?.state ?? '') ?? 51,
      modeId: modeId?.state ?? 'M0',
      boilingPoint: double.tryParse(boilingPoint?.state ?? '') ?? 100,
      keepWarmOn: keepWarm?.isOn ?? false,
      dechlorinationOn: dechlorination?.isOn ?? false,
      rapidCoolingOn: rapidCooling?.isOn ?? false,
      childLocked: lockStatus?.isOn ?? false,
      modeEntityId: modeEntity.entityId,
      targetEntityId: target?.entityId,
      keepWarmEntityId: keepWarm?.entityId,
      keepWarmTempEntityId: keepWarmTemp?.entityId,
      dechlorinationEntityId: dechlorination?.entityId,
      rapidCoolingEntityId: rapidCooling?.entityId,
      pureWaterTempEntityId: pureWaterTemp?.entityId,
      tapWaterTempEntityId: tapWaterTemp?.entityId,
      startEntityId:
          _find(entities, _idHas('_start_cook_a_2_1'))?.entityId,
      stopEntityId:
          _find(entities, _idHas('_cancel_cooking_a_2_2'))?.entityId,
      lockMode: lockMode?.state,
    );
  }

  final String deviceId;
  final String name;

  /// 工作状态：待机中 / 烧水中… / 保温中… / 关机 …
  final String status;

  /// 当前水温（℃）
  final double temperature;
  final String? fault;

  /// 内置模式：自来水 / 纯净水 / 凉白开
  final List<String> modes;
  final String mode;

  final double targetTemperature;
  final double keepWarmTemperature;
  final bool keepWarmOn;
  final bool dechlorinationOn;
  final bool rapidCoolingOn;
  final bool childLocked;

  /// 模式 id（text.*_mode_id，当前设备为 M0）
  final String? modeId;

  /// 沸点（自来水 / 凉白开的加热目标，通常 100℃）
  final double boilingPoint;

  /// 纯净水 / 自来水保温温度（开始加热动作的附加参数）
  final double pureWaterKeepWarmTemperature;
  final double tapWaterKeepWarmTemperature;

  final String? modeEntityId;
  final String? targetEntityId;
  final String? keepWarmEntityId;
  final String? keepWarmTempEntityId;
  final String? dechlorinationEntityId;
  final String? rapidCoolingEntityId;
  final String? pureWaterTempEntityId;
  final String? tapWaterTempEntityId;
  final String? startEntityId;
  final String? stopEntityId;

  /// 童锁策略（如「50℃及以上热水需要解锁」）
  final String? lockMode;

  /// 是否处于烧水/除氯/风冷/降温/保温过程中
  bool get isActive =>
      status.contains('烧水') ||
      status.contains('除氯') ||
      status.contains('风冷') ||
      status.contains('降温') ||
      status.contains('保温');

  /// 是否处于保温 / 降温阶段（此时停止按钮显示「停止保温」）
  bool get isKeepingWarm =>
      status.contains('保温') ||
      status.contains('降温') ||
      status.contains('风冷');

  /// 停止按钮文案：保温 / 降温 → 停止保温，其余 → 停止加热
  String get stopLabel => isKeepingWarm ? '停止保温' : '停止加热';

  /// 首页卡按钮文案：未运行「加热」，运行中按阶段显示停止文案
  String get cardActionLabel => isActive ? stopLabel : '加热';

  bool get isTapWater => mode == '自来水';
  bool get isPureWater => mode == '纯净水';
  bool get isBoiledWater => mode == '凉白开';

  /// 当前模式实际要加热到的温度：
  /// 纯净水用纯净水保温温度（66℃）；自来水和凉白开加热到沸点（100℃）。
  double get effectiveTargetTemperature =>
      isPureWater ? pureWaterKeepWarmTemperature : boilingPoint;

  /// 当前模式实际使用的保温温度：
  /// 纯净水 66℃、自来水 51℃、凉白开不保温。
  double get effectiveKeepWarmTemperature =>
      isPureWater ? pureWaterKeepWarmTemperature : tapWaterKeepWarmTemperature;

  /// 除氯只在自来水 / 凉白开模式显示
  bool get showDechlorination => !isPureWater;

  /// 保温开关只在纯净水模式显示
  bool get showKeepWarmSwitch => isPureWater;

  /// 保温温度只在自来水 / 纯净水模式显示
  bool get showKeepWarmTemperature => !isBoiledWater;

  /// 纯净水模式没有单独的「设定温度」滑条，直接用保温温度控制
  bool get showTargetSlider => false;

  /// 当前模式对应的保温温度实体：
  /// 纯净水 `p_2_13`、自来水 `p_2_14`，凉白开没有。
  String? get effectiveKeepWarmTempEntityId =>
      isPureWater
          ? pureWaterTempEntityId
          : (isTapWater ? tapWaterTempEntityId : null);

  bool get hasFault {
    final String? value = fault;
    return value != null && value != '无故障' && value.isNotEmpty;
  }

  double get minTargetTemperature => 40;
  double get maxTargetTemperature => 100;

  double get minKeepWarmTemperature => 40;
  double get maxKeepWarmTemperature => 95;

  /// 开始加热的 notify 参数（集成用 YAML 解析，必须是 8 项列表）：
  /// [模式id, 设定温度, 保温, 保温温度, 除氯, 风冷, 纯净水保温温度, 自来水保温温度]
  String get startMessage => '[${<String>[
        modeId ?? 'M0',
        effectiveTargetTemperature.round().toString(),
        (isBoiledWater ? false : keepWarmOn).toString(),
        effectiveKeepWarmTemperature.round().toString(),
        dechlorinationOn.toString(),
        rapidCoolingOn.toString(),
        pureWaterKeepWarmTemperature.round().toString(),
        tapWaterKeepWarmTemperature.round().toString(),
      ].join(', ')}]';

  static bool Function(HaEntityStateModel) _idHas(String part) =>
      (HaEntityStateModel e) => e.entityId.contains(part);

  static HaEntityStateModel? _find(
    Iterable<HaEntityStateModel> entities,
    bool Function(HaEntityStateModel) test,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (test(entity)) return entity;
    }
    return null;
  }
}

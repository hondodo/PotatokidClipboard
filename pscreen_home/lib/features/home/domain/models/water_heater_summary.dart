import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 热水器设备摘要：water_heater 主实体 + 工作状态 / 预热开关等辅助实体。
///
/// 米家燃气热水器在 HA 里由 `water_heater.*` 主实体加一批
/// switch/sensor/event 组合而成。本模型负责把主实体与「预热 / 定时预热 /
/// 工作状态 / 进水温度 / 水流量」组装起来，供首页卡片和详情面板使用。
class WaterHeaterSummary {
  const WaterHeaterSummary({
    required this.deviceId,
    required this.name,
    required this.entity,
    this.status,
    this.fault,
    this.inletTemperature,
    this.flowRate,
    this.preheatEntityId,
    this.preheatOn = false,
    this.timerPreheatEntityId,
    this.timerPreheatOn = false,
  });

  /// 从设备全部实体中解析；没有 water_heater 主实体时返回 null。
  static WaterHeaterSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    HaEntityStateModel? main;
    for (final HaEntityStateModel entity in entities) {
      if (entity.isWaterHeater) {
        main = entity;
        break;
      }
    }
    if (main == null) return null;

    final HaEntityStateModel? preheat = _findSwitch(
      entities,
      idSuffix: '_hot_water_recirculation',
      nameSuffix: ' 预热',
    );
    final HaEntityStateModel? timerPreheat = _findSwitch(
      entities,
      idSuffix: '_intelligent_preheat',
      nameSuffix: '智能定时预热',
    );

    return WaterHeaterSummary(
      deviceId: deviceId,
      name: name,
      entity: main,
      status: _bySuffix(entities, '工作状态', domain: 'sensor')?.state,
      fault: _bySuffix(entities, '故障', domain: 'sensor')?.state,
      inletTemperature: _number(
        _bySuffix(entities, '进水温度', domain: 'sensor')?.state,
      ),
      flowRate: _number(
        _findSensor(entities, '水流量')?.state,
      ),
      preheatEntityId: preheat?.entityId,
      preheatOn: preheat?.isOn ?? false,
      timerPreheatEntityId: timerPreheat?.entityId,
      timerPreheatOn: timerPreheat?.isOn ?? false,
    );
  }

  final String deviceId;
  final String name;

  /// water_heater 主实体（目标温度 / 当前温度 / 模式都从它取）
  final HaEntityStateModel entity;

  /// 工作状态（待机中 / 用水中 / 预热中 / 洗浴保温 / 防冻开启）
  final String? status;

  /// 故障码（0 表示正常）
  final String? fault;

  /// 进水温度（℃）
  final double? inletTemperature;

  /// 水流量（L/min）
  final double? flowRate;

  final String? preheatEntityId;
  final bool preheatOn;
  final String? timerPreheatEntityId;
  final bool timerPreheatOn;

  bool get isOn => entity.isOn;

  /// 可选洗浴模式（去掉 off）
  List<String> get modes => entity.operationModes
      .where((String mode) => mode != 'off')
      .toList(growable: false);

  /// 当前洗浴模式
  String get mode => entity.operationMode;

  double? get currentTemperature => entity.currentTemperature;

  double? get targetTemperature => entity.targetTemperature;

  double get minTemperature => entity.minTargetTemperature;

  double get maxTemperature => entity.maxTargetTemperature;

  double get targetStep => entity.targetTempStep;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != '0' &&
        value != 'unknown' &&
        value != 'unavailable' &&
        value.isNotEmpty;
  }

  String get statusLabel {
    if (!isOn) return '已关机';
    return status ?? mode;
  }

  static HaEntityStateModel? _findSwitch(
    Iterable<HaEntityStateModel> entities, {
    required String idSuffix,
    required String nameSuffix,
  }) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'switch') continue;
      if (entity.entityId.contains(idSuffix)) return entity;
      if (entity.displayName.trim().endsWith(nameSuffix)) return entity;
    }
    return null;
  }

  static HaEntityStateModel? _bySuffix(
    Iterable<HaEntityStateModel> entities,
    String suffix, {
    required String domain,
  }) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != domain) continue;
      if (entity.displayName.trim().endsWith(suffix)) return entity;
    }
    return null;
  }

  static HaEntityStateModel? _findSensor(
    Iterable<HaEntityStateModel> entities,
    String keyword,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'sensor') continue;
      if (entity.displayName.contains(keyword)) return entity;
    }
    return null;
  }

  static double? _number(String? raw) => raw == null ? null : double.tryParse(raw);
}

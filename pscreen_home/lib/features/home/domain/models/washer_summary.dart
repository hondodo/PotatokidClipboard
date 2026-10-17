import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 洗衣机设备摘要：从同一 device 下的全部实体中，按名称后缀找出
/// 状态、模式、按钮、统计等关键实体。
///
/// HA 没有 `washer` 域，米家洗衣机在 HA 里被拆成
/// `switch.*_on_p_2_1`、`select.*_mode_p_2_3`、`sensor.*_status_p_2_2`、
/// `button.*_start_wash_a_2_2` 等一批实体；本模型负责把它们组装成
/// 一套可渲染的摘要。找不到「工作状态 + 运行状态 + 模式」时返回 null，
/// 避免把普通设备误判成洗衣机。
class WasherSummary {
  const WasherSummary({
    required this.deviceId,
    required this.name,
    required this.status,
    required this.runStatus,
    required this.isOn,
    required this.modes,
    this.remainingMinutes,
    this.doorState,
    this.fault,
    this.mode,
    this.powerEntityId,
    this.modeEntityId,
    this.startEntityId,
    this.pauseEntityId,
    this.stopEntityId,
    this.energyKwh,
    this.waterConsumption,
    this.washedTimes,
  });

  /// 从设备全部实体中解析；不是洗衣机时返回 null。
  static WasherSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? status =
        _bySuffix(entities, '工作状态', domain: 'sensor');
    final HaEntityStateModel? runStatus =
        _bySuffix(entities, '运行状态', domain: 'sensor');
    final HaEntityStateModel? modeEntity =
        _bySuffix(entities, '模式', domain: 'select');
    if (status == null || runStatus == null || modeEntity == null) return null;

    final HaEntityStateModel? power = _findPowerSwitch(entities);
    final HaEntityStateModel? leftTime =
        _bySuffix(entities, '剩余时间', domain: 'sensor');
    final int? remaining = leftTime == null ? null : int.tryParse(leftTime.state);
    final HaEntityStateModel? energy =
        _bySuffix(entities, '耗电量', domain: 'sensor');
    final HaEntityStateModel? water =
        _bySuffix(entities, '耗水量', domain: 'sensor');
    final HaEntityStateModel? washed =
        _bySuffix(entities, '已洗涤次数', domain: 'sensor');

    return WasherSummary(
      deviceId: deviceId,
      name: name,
      status: status.state,
      runStatus: runStatus.state,
      isOn: power?.isOn ?? status.state != '已关机',
      modes: modeEntity.options,
      remainingMinutes: remaining != null && remaining > 0 ? remaining : null,
      doorState: _bySuffix(entities, '门状态', domain: 'sensor')?.state,
      fault: _bySuffix(entities, '故障', domain: 'sensor')?.state,
      mode: modeEntity.state,
      powerEntityId: power?.entityId,
      modeEntityId: modeEntity.entityId,
      startEntityId:
          _bySuffix(entities, '开始洗涤', domain: 'button')?.entityId,
      pauseEntityId: _bySuffix(entities, '暂停', domain: 'button')?.entityId,
      stopEntityId:
          _bySuffix(entities, '停止洗涤', domain: 'button')?.entityId,
      energyKwh: energy == null ? null : double.tryParse(energy.state),
      waterConsumption: water == null ? null : double.tryParse(water.state),
      washedTimes: washed == null ? null : int.tryParse(washed.state),
    );
  }

  final String deviceId;
  final String name;

  /// 工作状态（已关机 / 待机中 / 工作中 / 暂停中 / 洗涤完成 …）
  final String status;

  /// 运行状态（未运行 / 主洗中 / 漂洗中 / 脱水中 / 烘干中 …）
  final String runStatus;

  /// 电源开关状态
  final bool isOn;

  /// 全部可选模式（select 的 options）
  final List<String> modes;

  /// 剩余分钟数（>0 时才有值）
  final int? remainingMinutes;

  /// 门状态文案
  final String? doorState;

  /// 故障文案（"No Faults" 表示正常）
  final String? fault;

  /// 当前模式
  final String? mode;

  final String? powerEntityId;
  final String? modeEntityId;
  final String? startEntityId;
  final String? pauseEntityId;
  final String? stopEntityId;

  /// 累计耗电量（kWh）
  final double? energyKwh;

  /// 耗水量（HA 未提供单位）
  final double? waterConsumption;

  /// 累计洗涤次数
  final int? washedTimes;

  /// 是否正在运行
  bool get isRunning =>
      runStatus != '未运行' &&
      runStatus != 'unknown' &&
      runStatus != 'unavailable' &&
      runStatus.isNotEmpty;

  /// 是否有故障
  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != 'No Faults' &&
        value != '无故障' &&
        value != 'unknown' &&
        value.isNotEmpty;
  }

  /// 卡片 / 面板上展示的主状态文案
  String get statusLabel {
    if (!isOn && !isRunning) return '已关机';
    if (isRunning) {
      final int? left = remainingMinutes;
      return left == null ? runStatus : '$runStatus · 剩余 $left 分钟';
    }
    return status;
  }

  /// 找到真正的电源开关：`switch.*_on_p_2_1` 或名称最后一段为「开关」。
  static HaEntityStateModel? _findPowerSwitch(
    Iterable<HaEntityStateModel> entities,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'switch') continue;
      final String id = entity.entityId.toLowerCase();
      if (RegExp(r'_(on|power)(_p_\d+)?$').hasMatch(id)) return entity;
      final List<String> tokens = entity.displayName
          .split(RegExp(r'\s+'))
          .where((String token) => token.isNotEmpty)
          .toList(growable: false);
      if (tokens.isNotEmpty && tokens.last == '开关') return entity;
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
}

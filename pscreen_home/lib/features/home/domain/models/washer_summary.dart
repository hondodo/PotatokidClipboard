import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 洗衣机设备摘要：从同一 device 下的全部实体中，按**实体 id 的 MIoT 属性
/// 后缀**（如 `_status_p_2_2`、`_mode_p_2_3`）找出关键实体。
///
/// 不依赖 friendly_name：HA 里设备/实体改名后，显示名会变，但实体 id 里的
/// MIoT 属性后缀是集成生成的稳定标识。找不到「工作状态 + 模式」时返回 null，
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
        _byId(entities, '_status_p_2_2', domain: 'sensor');
    final HaEntityStateModel? modeEntity =
        _byId(entities, '_mode_p_2_3', domain: 'select');
    if (status == null || modeEntity == null) return null;

    // 12kg 有「运行状态」，10kg 只有「行程 stroke」，两者都归一到运行态。
    final HaEntityStateModel? runEntity =
        _byId(entities, '_run_status_p_2_11', domain: 'sensor') ??
            _byId(entities, '_stroke_p_3_6', domain: 'sensor');
    final String runStatus = _runLabel(runEntity?.state);

    final HaEntityStateModel? power = _findPowerSwitch(entities);
    final HaEntityStateModel? leftTime =
        _byId(entities, '_left_time_p_2_10', domain: 'sensor');
    final int? remaining =
        leftTime == null ? null : int.tryParse(leftTime.state);
    final HaEntityStateModel? energy =
        _byId(entities, '_power_consumption_p_2_39', domain: 'sensor');
    final HaEntityStateModel? water =
        _byId(entities, '_water_consumption_p_2_40', domain: 'sensor');
    final HaEntityStateModel? washed =
        _byId(entities, '_has_washed_times_p_2_13', domain: 'sensor');

    return WasherSummary(
      deviceId: deviceId,
      name: name,
      status: status.state,
      runStatus: runStatus,
      isOn: power?.isOn ??
          (status.state != '已关机' && status.state != '关机中'),
      modes: modeEntity.options,
      remainingMinutes:
          remaining != null && remaining > 0 ? remaining : null,
      doorState: _byId(entities, '_door_state_p_2_9', domain: 'sensor')?.state,
      fault: _byId(entities, '_fault_p_2_4', domain: 'sensor')?.state,
      mode: modeEntity.state,
      powerEntityId: power?.entityId,
      modeEntityId: modeEntity.entityId,
      startEntityId:
          _byId(entities, '_start_wash_', domain: 'button')?.entityId,
      pauseEntityId:
          _byId(entities, '_pause_a_2_', domain: 'button')?.entityId,
      stopEntityId:
          _byId(entities, '_stop_washing_', domain: 'button')?.entityId,
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
  bool get isRunning {
    if (status.contains('工作') ||
        status.contains('洗') ||
        status.contains('烘') ||
        status.contains('漂') ||
        status.contains('脱')) {
      return true;
    }
    return runStatus.isNotEmpty && runStatus != '未运行';
  }

  /// 是否有故障
  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return !value.startsWith('无故障') &&
        value != 'No Faults' &&
        value != 'unknown' &&
        value.isNotEmpty;
  }

  /// 卡片 / 面板上展示的主状态文案
  String get statusLabel {
    if (!isOn && !isRunning) return '已关机';
    if (isRunning) {
      final int? left = remainingMinutes;
      final String state = runStatus.isEmpty ? status : runStatus;
      return left == null ? state : '$state · 剩余 $left 分钟';
    }
    return status;
  }

  /// 找到真正的电源开关：只认实体 id 的 `_on_p_2_1` / `_power` 后缀，
  /// 避免显示名改名后误选提示音之类。
  static HaEntityStateModel? _findPowerSwitch(
    Iterable<HaEntityStateModel> entities,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'switch') continue;
      final String id = entity.entityId.toLowerCase();
      if (id.endsWith('_on_p_2_1') || id.endsWith('_power')) return entity;
    }
    return null;
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

  /// 行程 / 运行状态归一化；未知英文值原样返回。
  static String _runLabel(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty || value == 'None' || value == '未运行') return '';
    return switch (value) {
      'Weighing' => '称重中',
      'Washing' => '洗涤中',
      'Rinsing' => '漂洗中',
      'Spin' => '脱水中',
      'Drying' => '烘干中',
      _ => value,
    };
  }
}

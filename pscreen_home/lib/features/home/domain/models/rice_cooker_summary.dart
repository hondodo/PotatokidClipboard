import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 电饭煲摘要：工作状态、剩余时长、食谱 id、开始/停止。
///
/// 米家菜谱（精煮饭 / 快煮饭 / 煮粥 / 扩展模式）定义在云端，HA 只暴露
/// `menu_id` 和“设置食谱”动作，因此只支持按当前 menu_id 开始与停止。
class RiceCookerSummary {
  const RiceCookerSummary({
    required this.deviceId,
    required this.name,
    required this.status,
    required this.menuId,
    this.fault,
    this.remainingMinutes,
    this.totalMinutes,
    this.keepWarmMinutes,
    this.autoKeepWarm = false,
    this.startEntityId,
    this.stopEntityId,
  });

  static RiceCookerSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? status =
        _byId(entities, '_status_p_2_1', domain: 'sensor');
    final HaEntityStateModel? start =
        _byId(entities, '_start_cook_a_2_1', domain: 'notify');
    // 电热水瓶也共用 `status_p_2_1` / `start_cook_a_2_1`，必须再用电饭煲
    // 独有事件 `cooking_finished_e_2_1` 兜底，避免把热水瓶当成电饭煲。
    final HaEntityStateModel? finished =
        _byId(entities, '_cooking_finished_e_2_1', domain: 'event');
    if (status == null || start == null || finished == null) return null;

    final HaEntityStateModel? stop =
        _byId(entities, '_cancel_cooking_a_2_2', domain: 'button');
    final HaEntityStateModel? menu =
        _byId(entities, '_menu_id_p_3_1', domain: 'sensor');
    final HaEntityStateModel? remaining =
        _byId(entities, '_left_time_p_3_3', domain: 'sensor');
    final HaEntityStateModel? total =
        _byId(entities, '_cook_total_time_p_3_2', domain: 'sensor');
    final int? remainingSeconds = _int(remaining?.state);
    final int? totalMinutes = _int(total?.state);
    final int? remainingMinutes = remainingSeconds == null
        ? null
        : (remainingSeconds / 60).ceil();
    final HaEntityStateModel? keepWarmTime =
        _byId(entities, '_keepwarm_time_p_3_4', domain: 'sensor');
    final HaEntityStateModel? autoKeepWarm = _byId(
      entities,
      '_auto_keepwarm_flag_p_3_5',
      domain: 'binary_sensor',
    );

    return RiceCookerSummary(
      deviceId: deviceId,
      name: name,
      status: status.state,
      menuId: _int(menu?.state) ?? 0,
      fault: _byId(entities, '_fault_p_2_2', domain: 'sensor')?.state,
      remainingMinutes: remainingMinutes,
      totalMinutes: totalMinutes,
      keepWarmMinutes: _int(keepWarmTime?.state),
      autoKeepWarm: autoKeepWarm?.state == 'on',
      startEntityId: start.entityId,
      stopEntityId: stop?.entityId,
    );
  }

  final String deviceId;
  final String name;
  final String status;
  final int menuId;
  final String? fault;
  final int? remainingMinutes;
  final int? totalMinutes;
  final int? keepWarmMinutes;
  final bool autoKeepWarm;
  final String? startEntityId;
  final String? stopEntityId;

  bool get hasFault {
    final String? value = fault;
    if (value == null) return false;
    return value != 'No Faults' &&
        value != '无故障' &&
        value != 'unknown' &&
        value.isNotEmpty;
  }

  bool get isActive =>
      status.contains('烹饪') ||
      status.contains('加热') ||
      status.contains('煮') ||
      status.contains('保温') ||
      status.contains('工作');

  String get statusLabel {
    if (hasFault) return '故障';
    final int? left = remainingMinutes;
    if (isActive && left != null && left > 0) {
      return '$status · 剩余 ${_duration(left)}';
    }
    return status;
  }

  String get startMessage => '[${menuId > 0 ? menuId : 1}]';

  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
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

  static int? _int(String? raw) => raw == null ? null : int.tryParse(raw);
}

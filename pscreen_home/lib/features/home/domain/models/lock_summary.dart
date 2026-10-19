import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 门锁设备摘要：是否已上锁 + 各电池剩余电量 + 电量更新时间。
///
/// 识别**不依赖 friendly_name**（HA 里改名会变），按实体 id / 属性匹配。
/// 以实测的鹿客门锁（`loock_cn_*_t2pv1`）为基准：
/// - 上锁状态：`lock.*` 域，或 `sensor` / `binary_sensor` 的 id 含
///   `_door_state_` / `_lock_state_` / `_lock_status_`（MIoT 属性名稳定）；
/// - 电池：`device_class == battery` 的 `sensor`（门锁本体 / 猫眼各一块）；
/// - 电量更新时间：id 含 `battery_update_time` / `update_time` / `last_update`
///   的 Unix 秒 / 毫秒时间戳传感器；不会误取 `online_timestamp`。
///
/// 找不到上锁状态实体时返回 null，避免把普通带电池的设备误判成门锁。
class LockSummary {
  const LockSummary({
    required this.deviceId,
    required this.name,
    required this.locked,
    required this.stateText,
    required this.batteries,
    required this.batteryUpdatedAt,
    required this.stateEntityId,
    required this.batteryUpdateEntityId,
  });

  /// 从设备全部实体中解析；不是门锁时返回 null。
  static LockSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? stateEntity = _findLockState(entities);
    if (stateEntity == null) return null;

    final List<LockBattery> batteries = <LockBattery>[
      for (final HaEntityStateModel entity in entities)
        if (_isBattery(entity))
          LockBattery(
            label: _batteryLabel(entity, name),
            percent: _percentOf(entity.state),
            entityId: entity.entityId,
          ),
    ];
    final HaEntityStateModel? updateEntity = _findBatteryUpdateTime(entities);

    return LockSummary(
      deviceId: deviceId,
      name: name,
      locked: _parseLocked(stateEntity.state, allowOnOff: true),
      stateText: stateEntity.state,
      batteries: batteries,
      batteryUpdatedAt: _parseTimestamp(updateEntity?.state),
      stateEntityId: stateEntity.entityId,
      batteryUpdateEntityId: updateEntity?.entityId,
    );
  }

  final String deviceId;
  final String name;

  /// 是否已上锁；无法识别时为 null
  final bool? locked;

  /// 上锁状态实体的原始状态文案
  final String stateText;

  /// 各电池剩余电量（通常为「电池」+「猫眼电池」）
  final List<LockBattery> batteries;

  /// 电量更新时间（已转换为本地时间）
  final DateTime? batteryUpdatedAt;

  /// 上锁状态实体 id（详情页从原始列表隐藏）
  final String stateEntityId;

  /// 电量更新时间实体 id（详情页从原始列表隐藏）
  final String? batteryUpdateEntityId;

  /// 状态文案：已上锁 / 未上锁 / 原始状态
  String get statusLabel {
    final bool? value = locked;
    if (value == null) return stateText.isEmpty ? '未知' : stateText;
    return value ? '已上锁' : '未上锁';
  }

  /// 详情页顶部卡片已经展示、需要从原始实体列表隐藏的实体 id
  List<String> get infoEntityIds => <String>[
        stateEntityId,
        for (final LockBattery battery in batteries) battery.entityId,
        ?batteryUpdateEntityId,
      ];

  /// 电量更新时间完整文案（本地时间，`yyyy-MM-dd HH:mm`）
  String? get batteryUpdatedLabel {
    final DateTime? time = batteryUpdatedAt;
    if (time == null) return null;
    final DateTime local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// 卡片上的短文案（本地时间，`MM-dd HH:mm`）
  String? get batteryUpdatedShortLabel {
    final DateTime? time = batteryUpdatedAt;
    if (time == null) return null;
    final DateTime local = time.toLocal();
    return '${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static HaEntityStateModel? _findLockState(
    Iterable<HaEntityStateModel> entities,
  ) {
    // 1. 标准 lock 域（若设备直接暴露 lock 实体）
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain == 'lock' && entity.isAvailable) return entity;
    }
    // 2. 米家 / 鹿客门锁：MIoT 属性名 door_state 稳定，不随 friendly_name 变。
    //    实测 id：sensor.loock_*_door_state_p_3_1021 = 已上锁 / 未上锁。
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'sensor' && entity.domain != 'binary_sensor') {
        continue;
      }
      if (!entity.isAvailable) continue;
      final String id = entity.entityId.toLowerCase();
      if (id.contains('_door_state_') ||
          id.contains('_lock_state_') ||
          id.contains('_lock_status_')) {
        return entity;
      }
    }
    return null;
  }

  static bool _isBattery(HaEntityStateModel entity) {
    if (entity.domain != 'sensor') return false;
    final String id = entity.entityId.toLowerCase();
    if (id.contains('temperature') || id.contains('temp_')) return false;
    final String? deviceClass = entity.attributes['device_class']?.toString();
    // 实测两块电池都带 device_class=battery，且 id 含 battery_level。
    // 只按结构识别，不使用 friendly_name。
    final bool looksBattery =
        deviceClass == 'battery' || id.contains('battery');
    if (!looksBattery) return false;
    final int? percent = _percentOf(entity.state);
    return percent != null;
  }

  static HaEntityStateModel? _findBatteryUpdateTime(
    Iterable<HaEntityStateModel> entities,
  ) {
    // 实测：sensor.loock_*_battery_update_time_p_11_15 = 1792414663 s。
    // 注意同设备还有 online_timestamp（联网时间戳），不能当成电量更新时间。
    HaEntityStateModel? fallback;
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != 'sensor') continue;
      if (_parseTimestamp(entity.state) == null) continue;
      final String id = entity.entityId.toLowerCase();
      if (id.contains('battery_update_time') ||
          id.contains('update_time') ||
          id.contains('updated_time') ||
          id.contains('last_update')) {
        return entity;
      }
      // 兜底：id 含 battery 的时间戳（不含 online_timestamp）。
      if (id.contains('battery') && id.contains('time')) {
        fallback ??= entity;
      }
    }
    return fallback;
  }

  static int? _percentOf(String raw) {
    final double? value = double.tryParse(raw.trim());
    if (value == null || value < 0 || value > 100) return null;
    return value.round();
  }

  /// 电池名：`门锁 猫眼电池 电池电量` → `猫眼电池`，`门锁 电池 电池电量` → `电池`。
  ///
  /// friendly_name 只用于展示标签，不参与设备类型识别。
  static String _batteryLabel(HaEntityStateModel entity, String deviceName) {
    String name = entity.displayName.trim();
    if (deviceName.isNotEmpty && name.startsWith(deviceName)) {
      name = name.substring(deviceName.length).trim();
    }
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 2 && parts.last.contains('电量')) {
      return parts[parts.length - 2];
    }
    if (name.isEmpty || name == deviceName || name.contains('电池电量')) {
      return '电池';
    }
    return name;
  }

  static bool? _parseLocked(String raw, {required bool allowOnOff}) {
    final String value = raw.trim();
    final String lower = value.toLowerCase();
    if (lower == 'locked' ||
        lower == 'locking' ||
        value == '已上锁' ||
        value == '已锁定' ||
        value == '上锁') {
      return true;
    }
    if (lower == 'unlocked' ||
        lower == 'unlocking' ||
        value == '未上锁' ||
        value == '已开锁' ||
        value == '已解锁' ||
        value == '开锁') {
      return false;
    }
    if (allowOnOff) {
      if (lower == 'on') return true;
      if (lower == 'off') return false;
    }
    return null;
  }

  static DateTime? _parseTimestamp(String? raw) {
    final int? value = raw == null ? null : int.tryParse(raw.trim());
    if (value == null) return null;
    // 毫秒时间戳（13 位）
    if (value >= 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    // 秒时间戳（10 位，约 2001-5138 年）
    if (value >= 1000000000 && value < 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return null;
  }
}

/// 单块电池的剩余电量。
class LockBattery {
  const LockBattery({
    required this.label,
    required this.percent,
    required this.entityId,
  });

  /// 电池名（电池 / 猫眼电池 …）
  final String label;

  /// 剩余百分比（0-100）
  final int? percent;

  final String entityId;

  String get valueLabel => percent == null ? '—' : '$percent%';
}

/// Home Assistant 区域（房间）。
class HaArea {
  const HaArea({
    required this.areaId,
    required this.name,
    this.position = 0,
  });

  final String areaId;
  final String name;

  /// HA 前端的区域排序值（缺失视为 0，保持注册表原始顺序）
  final int position;
}

/// Home Assistant 设备：实体未直接指定房间时，回退到设备所属房间。
class HaDevice {
  const HaDevice({
    required this.id,
    required this.name,
    this.areaId,
  });

  final String id;

  /// 展示名：优先 name_by_user，其次 name
  final String name;
  final String? areaId;
}

/// 注册表快照：房间列表 + 设备表 + 实体 → 房间 映射。
///
/// 数据来源为 HA 的三个注册表接口
/// （config/area_registry/list、config/device_registry/list、
/// config/entity_registry/list），由 data 层组装；
/// 归属规则：实体自身 area_id > 所属设备的 area_id。
class HaRegistry {
  const HaRegistry({
    this.areas = const <HaArea>[],
    this.devices = const <String, HaDevice>{},
    this.areaIdByEntity = const <String, String>{},
  });

  /// 空注册表（注册表拉取失败时降级使用，主页功能不受影响）
  static const HaRegistry empty = HaRegistry();

  /// 房间列表（已按 HA 的 position 排好序）
  final List<HaArea> areas;

  /// 设备表，key 为设备 id
  final Map<String, HaDevice> devices;

  /// 实体 id → 所属房间 id（仅收录已分配房间的实体）
  final Map<String, String> areaIdByEntity;

  /// 实体所属房间 id（未分配返回 null）
  String? areaIdOf(String entityId) => areaIdByEntity[entityId];

  /// 实体所属房间名（未分配返回 null）
  String? areaNameOf(String entityId) {
    final String? id = areaIdOf(entityId);
    if (id == null) return null;
    for (final HaArea area in areas) {
      if (area.areaId == id) return area.name;
    }
    return null;
  }
}

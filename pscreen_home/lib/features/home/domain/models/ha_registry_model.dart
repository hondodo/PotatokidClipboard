/// Home Assistant 区域（房间）。
///
/// **家庭归属约定**：区域名按 `家庭名 房间名` 存储（如「金科1204 客厅」），
/// 首个空格前为家庭名；无空格的区域视为未分配家庭。
/// HA 注册表本身没有独立的「家庭」层级（floor / label 均为空表），
/// 家庭信息只能从命名解析，因此**家庭名不能包含空格**。
class HaArea {
  const HaArea({required this.areaId, required this.name, this.position = 0});

  final String areaId;
  final String name;

  /// HA 前端的区域排序值（缺失视为 0，保持注册表原始顺序）
  final int position;

  /// 家庭名（区域名首个空格之前；无前缀返回 `''`）
  String get homeName {
    final int index = name.indexOf(' ');
    return index > 0 ? name.substring(0, index) : '';
  }

  /// 房间名（家庭名之后的部分；无家庭前缀时等于区域名）
  String get roomName {
    final int index = name.indexOf(' ');
    return index > 0 ? name.substring(index + 1) : name;
  }
}

/// Home Assistant 设备：实体未直接指定房间时，回退到设备所属房间。
class HaDevice {
  const HaDevice({required this.id, required this.name, this.areaId});

  final String id;

  /// 展示名：优先 name_by_user，其次 name
  final String name;
  final String? areaId;
}

/// 注册表快照：房间列表 + 设备表 + 实体 → 房间/设备 映射。
///
/// 数据来源为 HA 的三个注册表接口
/// （config/area_registry/list、config/device_registry/list、
/// config/entity_registry/list），由 data 层组装；
/// 房间归属规则：实体自身 area_id > 所属设备的 area_id；
/// 设备归属直接取实体注册表的 device_id。
class HaRegistry {
  const HaRegistry({
    this.areas = const <HaArea>[],
    this.devices = const <String, HaDevice>{},
    this.areaIdByEntity = const <String, String>{},
    this.deviceIdByEntity = const <String, String>{},
  });

  /// 空注册表（注册表拉取失败且无本地缓存时降级使用，主页功能不受影响）
  static const HaRegistry empty = HaRegistry();

  /// 房间列表（已按 HA 的 position 排好序）
  final List<HaArea> areas;

  /// 设备表，key 为设备 id
  final Map<String, HaDevice> devices;

  /// 实体 id → 所属房间 id（仅收录已分配房间的实体）
  final Map<String, String> areaIdByEntity;

  /// 实体 id → 所属设备 id（仅收录有设备归属的实体）
  final Map<String, String> deviceIdByEntity;

  /// 实体所属房间 id（未分配返回 null）
  String? areaIdOf(String entityId) => areaIdByEntity[entityId];

  /// 实体所属设备 id（未分配返回 null）
  String? deviceIdOf(String entityId) => deviceIdByEntity[entityId];

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

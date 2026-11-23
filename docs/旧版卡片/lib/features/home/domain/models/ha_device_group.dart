import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 设备分组：同一物理设备下的**全部实体**，合并为网格上的一张卡片。
///
/// 一个 HA 设备（device_registry 条目）常暴露多个实体
/// （如米家风扇灯 = 灯 + 凌动开关 + 延时 + 夜灯 + 传感器…），逐实体铺卡
/// 会把同一物理设备拆成十几张。分组后：
///
/// - [title]：设备名（注册表 name_by_user > name，缺失回退首个实体显示名）；
/// - [entities]：该设备全部实体（可用在前，不可用在后；可用部分按
///   真灯 > 空调/热水器 > 主电源开关 > 其他 switch > 指示灯 > 数据/动作排序，
///   主实体永远排首位）；
/// - [primary]：主实体（可开关域内选取），外层卡片快捷开关只操作它；
///   组内无可开关实体时为 null，卡片不显示电源键；
/// - 聚合状态：[statusLabel]，开关类显示「已开启 x/y」，纯数据显示
///   「可用 x/y」，全部离线显示「不可用」。
///
/// **不按 domain 过滤**：数据类（sensor 等）以值 label 展示、
/// 动作类（button 等）展示但不交互、unavailable 置灰排组内末尾——
/// 全部实体可见，避免「HA 里有、面板上找不到」的困惑。
class HaDeviceGroup {
  HaDeviceGroup({
    required this.deviceId,
    required this.title,
    required List<HaEntityStateModel> entities,
  }) : entities = _sorted(List<HaEntityStateModel>.of(entities)) {
    if (entities.isEmpty) {
      throw ArgumentError('HaDeviceGroup.entities 不能为空');
    }
  }

  /// 按设备归属分组。
  static List<HaDeviceGroup> group({
    required Map<String, HaEntityStateModel> entities,
    required String? Function(String entityId) deviceIdOf,
    required String? Function(String deviceId) deviceNameOf,
  }) {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel e in entities.values) {
      final String key = deviceIdOf(e.entityId) ?? 'entity:${e.entityId}';
      byDevice.putIfAbsent(key, () => <HaEntityStateModel>[]).add(e);
    }

    final List<HaDeviceGroup> groups = <HaDeviceGroup>[];
    byDevice.forEach((String key, List<HaEntityStateModel> list) {
      final String? deviceId = key.startsWith('entity:') ? null : key;
      final String title =
          (deviceId != null ? deviceNameOf(deviceId) : null) ??
          list.first.displayName;
      groups.add(
        HaDeviceGroup(deviceId: deviceId, title: title, entities: list),
      );
    });

    groups.sort(_compareGroups);
    return groups;
  }

  /// 所属设备 id（null = 无设备归属，仅一个实体）
  final String? deviceId;

  /// 设备名（无设备归属时为实体显示名）
  final String title;

  /// 卡片稳定标识：用于持久化拖拽顺序。
  ///
  /// 有设备归属用 `device:<device_id>`，否则退化为
  /// `entity:<entity_id>`（此时组内只有一个实体）。
  /// 不要用标题或下标，改名/新增卡片都会让顺序失效。
  String get orderKey => deviceId == null
      ? 'entity:${entities.first.entityId}'
      : 'device:$deviceId';

  /// 该设备的全部实体（已排序，主实体在首位）
  final List<HaEntityStateModel> entities;

  /// 组内可开关实体
  Iterable<HaEntityStateModel> get switchableEntities =>
      entities.where((HaEntityStateModel e) => e.isSwitchable);

  /// 主实体：外层卡片快捷开关的操作目标。
  /// 组内无可开关实体时为 null（纯数据 / 动作 / 全离线设备）。
  HaEntityStateModel? get primary {
    for (final HaEntityStateModel e in entities) {
      if (e.isSwitchable) return e;
    }
    return null;
  }

  /// 组内空调实体（首页用它渲染温度卡片），没有则为 null
  HaEntityStateModel? get climate {
    for (final HaEntityStateModel entity in entities) {
      if (entity.isClimate) return entity;
    }
    return null;
  }

  /// 组内热水器实体，没有则为 null
  HaEntityStateModel? get waterHeater {
    for (final HaEntityStateModel entity in entities) {
      if (entity.isWaterHeater) return entity;
    }
    return null;
  }

  /// 是否为多实体设备（单实体卡片可保留轻量样式）
  bool get isMerged => entities.length > 1;

  /// 组内是否全部不可用（卡片置灰、不可点击）
  bool get isUnavailable =>
      entities.every((HaEntityStateModel e) => e.isUnavailable);

  /// 组内可用实体数
  int get availableCount =>
      entities.where((HaEntityStateModel e) => e.isAvailable).length;

  /// 可开关实体中已开启数量
  int get onCount =>
      switchableEntities.where((HaEntityStateModel e) => e.isOn).length;

  /// 可开关实体总数
  int get switchableCount => switchableEntities.length;

  /// 是否有可开关实体处于开启
  bool get anyOn => onCount > 0;

  /// 是否全部关闭（无开启的可开关实体）
  bool get allOff => onCount == 0;

  /// 聚合状态文案：
  /// - 全部离线 → 「不可用」；
  /// - 有可开关实体 → 全关「已关闭」/ 开「已开启 x/y」；
  /// - 无开关类（纯数据/动作）→ 「可用 x/y」。
  String get statusLabel {
    if (isUnavailable) return '不可用';
    if (switchableCount == 0) return '可用 $availableCount/${entities.length}';
    return onCount == 0 ? '已关闭' : '已开启 $onCount/$switchableCount';
  }

  /// 任一实体指令执行中（外层卡片显示 loading）
  bool isTogglingIn(Set<String> togglingIds) =>
      entities.any((HaEntityStateModel e) => togglingIds.contains(e.entityId));

  /// 组间排序：全不可用组排最后，其余按主实体权重，再按设备名。
  static int _compareGroups(HaDeviceGroup a, HaDeviceGroup b) {
    if (a.isUnavailable != b.isUnavailable) return a.isUnavailable ? 1 : -1;
    final int byWeight = _sortWeight(
      a.primary ?? a.entities.first,
    ).compareTo(_sortWeight(b.primary ?? b.entities.first));
    return byWeight != 0 ? byWeight : a.title.compareTo(b.title);
  }

  /// 组内排序：可用在前、不可用在后；可用部分按主实体权重。
  static List<HaEntityStateModel> _sorted(List<HaEntityStateModel> list) {
    list.sort((HaEntityStateModel a, HaEntityStateModel b) {
      if (a.isUnavailable != b.isUnavailable) return a.isUnavailable ? 1 : -1;
      final int byWeight = _sortWeight(a).compareTo(_sortWeight(b));
      return byWeight != 0 ? byWeight : a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  /// 实体排序权重：
  /// 真灯(0) > 空调/热水器(1) > 主电源开关(2) > 其他 switch(3) >
  /// 指示灯类 light(4) > 数据/动作类(5)。
  static int _sortWeight(HaEntityStateModel e) {
    if (!e.isSwitchable) return 5;
    if (e.domain == 'light') {
      final String id = e.entityId.toLowerCase();
      final bool indicatorLike =
          id.contains('indicator') ||
          id.contains('night_light') ||
          id.contains('ambient_light');
      return indicatorLike ? 4 : 0;
    }
    if (e.domain == 'climate' || e.domain == 'water_heater') return 1;
    if (e.domain == 'fan') return 1;
    if (e.domain == 'switch') return _isMainPowerSwitch(e) ? 2 : 3;
    return 3;
  }

  /// 是否为设备的真正电源开关（而非提示音、睡眠模式等设置开关）。
  ///
  /// 只认实体 id 的 `_on_p_x_x` / `_power` 后缀；不再用显示名兜底，
  /// 避免改名后把「提示音 / 静音」误选成主开关。
  static bool _isMainPowerSwitch(HaEntityStateModel e) {
    if (e.domain != 'switch') return false;
    final String id = e.entityId.toLowerCase();
    return id.endsWith('_power') || id.endsWith('_on') || id.contains('_on_p_');
  }
}

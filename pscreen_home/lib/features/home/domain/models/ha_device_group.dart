import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 设备分组：同一物理设备下的全部可控实体，合并为网格上的一张卡片。
///
/// 一个 HA 设备（device_registry 条目）常暴露多个可控实体
/// （如米家风扇灯 = 灯 + 凌动开关 + 延时 + 夜灯 + 墙壁开关…共 9 个），
/// 逐实体铺卡会把同一物理设备拆成十几张。分组后：
///
/// - [title]：设备名（注册表 name_by_user > name，缺失回退主实体显示名）；
/// - [entities]：该设备全部可控实体（已按优先级排序，主实体在首位）；
/// - [primary]：主实体，外层卡片的快捷开关只操作它
///   （取第一个非「指示灯/夜灯/氛围灯」的 light，否则第一个 switch，
///   否则第一个可控实体）；
/// - 聚合状态：[onCount] / [allOff] / [statusLabel]，供外层卡片展示
///   「已开启 2/9」这类必要详情。
///
/// 无设备归属的实体自成一组（deviceId 为 null，title 用主实体显示名），
/// 保证注册表降级为空时网格退化为「一实体一卡」，功能不受影响。
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
  ///
  /// [entities]：全部可控实体（switchable）；
  /// [deviceIdOf]：实体 id → 设备 id（HaRegistry.deviceIdOf）；
  /// [deviceNameOf]：设备 id → 设备名（HaRegistry.devices 查名）。
  ///
  /// 返回的分组按主实体域排序（灯在前），每组内部主实体在首位。
  static List<HaDeviceGroup> group({
    required Map<String, HaEntityStateModel> entities,
    required String? Function(String entityId) deviceIdOf,
    required String? Function(String deviceId) deviceNameOf,
  }) {
    // 按设备 id 聚合；无归属实体各自成组（key 用实体 id 保证唯一）
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel e in entities.values) {
      final String key = deviceIdOf(e.entityId) ?? 'entity:${e.entityId}';
      byDevice.putIfAbsent(key, () => <HaEntityStateModel>[]).add(e);
    }

    final List<HaDeviceGroup> groups = <HaDeviceGroup>[];
    byDevice.forEach((String key, List<HaEntityStateModel> list) {
      final String? deviceId = key.startsWith('entity:') ? null : key;
      final String title = (deviceId != null ? deviceNameOf(deviceId) : null) ??
          list.first.displayName;
      groups.add(HaDeviceGroup(
        deviceId: deviceId,
        title: title,
        entities: list,
      ));
    });

    groups.sort((HaDeviceGroup a, HaDeviceGroup b) {
      // 灯类设备在前（与实体级排序「灯在前开关在后」保持一致）
      final int byDomain =
          _primaryWeight(a.primary).compareTo(_primaryWeight(b.primary));
      return byDomain != 0 ? byDomain : a.title.compareTo(b.title);
    });
    return groups;
  }

  /// 所属设备 id（null = 无设备归属，仅一个实体）
  final String? deviceId;

  /// 设备名（无设备归属时为主实体显示名）
  final String title;

  /// 该设备的可控实体（已排序，主实体在首位）
  final List<HaEntityStateModel> entities;

  /// 主实体：外层卡片快捷开关的操作目标
  HaEntityStateModel get primary => entities.first;

  /// 是否为多实体设备（单实体卡片可保留轻量样式）
  bool get isMerged => entities.length > 1;

  /// 已开启数量
  int get onCount => entities.where((HaEntityStateModel e) => e.isOn).length;

  /// 是否有实体处于开启
  bool get anyOn => entities.any((HaEntityStateModel e) => e.isOn);

  /// 是否全部关闭
  bool get allOff => onCount == 0;

  /// 聚合状态文案：全部关闭 → 「已关闭」；有开启 → 「已开启 x/y」
  String get statusLabel => allOff
      ? '已关闭'
      : anyOn
          ? '已开启 $onCount/${entities.length}'
          : '不可用';

  /// 任一实体指令执行中（外层卡片显示 loading）
  bool isTogglingIn(Set<String> togglingIds) =>
      entities.any((HaEntityStateModel e) => togglingIds.contains(e.entityId));

  /// 组内排序 + 主实体选取：真灯(0) > switch(1) > 指示灯类 light(2)。
  ///
  /// 排除「指示灯/夜灯/氛围灯」命名的 light——它们只是设备状态灯，
  /// 不该被当作快捷开关的目标（如阳台植物灯的 light.indicator_light：
  /// 主控应是电源 switch，而不是常亮的指示灯）。
  static List<HaEntityStateModel> _sorted(List<HaEntityStateModel> list) {
    list.sort((HaEntityStateModel a, HaEntityStateModel b) {
      final int byWeight = _primaryWeight(a).compareTo(_primaryWeight(b));
      return byWeight != 0 ? byWeight : a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  static int _primaryWeight(HaEntityStateModel e) {
    final String name = e.displayName;
    final bool indicatorLike = name.contains('指示灯') ||
        name.contains('夜灯') ||
        name.contains('氛围灯');
    if (e.domain == 'light') return indicatorLike ? 2 : 0;
    return 1;
  }
}

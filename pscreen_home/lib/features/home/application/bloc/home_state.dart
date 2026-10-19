import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/air_fryer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
import 'package:pscreen_home/features/home/domain/models/rice_cooker_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_purifier_summary.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';
import 'package:pscreen_home/features/home/domain/models/home_climate_summary.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/domain/models/lock_summary.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';

/// 主页状态（不可变，通过 copyWith 更新）。
///
/// 筛选层级：家庭（区域名前缀解析） ▸ 房间 ▸ 实体。
class HomeState {
  const HomeState._({
    required this.isLoading,
    required this.entities,
    required this.togglingIds,
    required this.registry,
    required this.selectedHomeName,
    required this.selectedAreaId,
    this.errorMessage,
    this.errorType,
  });

  /// 初始状态。
  factory HomeState.initial() => const HomeState._(
        isLoading: false,
        entities: <String, HaEntityStateModel>{},
        togglingIds: <String>{},
        registry: HaRegistry.empty,
        selectedHomeName: '',
        selectedAreaId: '',
        errorMessage: null,
        errorType: null,
      );

  final bool isLoading;

  /// 全部实体状态，key 为 entity_id
  final Map<String, HaEntityStateModel> entities;

  /// 正在执行开关指令的实体 id（卡片显示 loading）
  final Set<String> togglingIds;

  /// 注册表快照（房间 / 设备 / 实体归属）
  final HaRegistry registry;

  /// 当前选中的家庭名，`''` 表示「全部」
  final String selectedHomeName;

  /// 当前选中的房间 id，`''` 表示「全部」
  final String selectedAreaId;

  final String? errorMessage;
  final NetErrorType? errorType;

  /// 可筛选的房间：含有任意实体的房间，保持注册表顺序。
  List<HaArea> get availableAreas {
    final Set<String> areaIds = <String>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? areaId = registry.areaIdOf(entity.entityId);
      if (areaId != null) areaIds.add(areaId);
    }
    return registry.areas
        .where((HaArea area) => areaIds.contains(area.areaId))
        .toList(growable: false);
  }

  /// 家庭温湿度概览（按家庭标签顺序）。
  ///
  /// 数据来自该家庭内 climate 实体的 `current_temperature` /
  /// `current_humidity`：优先取同时具备温湿度的设备，其次温度、湿度。
  /// 缺少数据的家庭仍返回条目，但对应字段为 null（界面不显示）。
  List<HomeClimateSummary> get homeClimateSummaries {
    final Map<String, String> homeByArea = <String, String>{
      for (final HaArea area in registry.areas) area.areaId: area.homeName,
    };
    final Map<String, HaEntityStateModel> sourceByHome =
        <String, HaEntityStateModel>{};
    final Map<String, int> scoreByHome = <String, int>{};

    for (final HaEntityStateModel entity in entities.values) {
      if (!entity.isClimate || !entity.isAvailable) continue;
      final String? areaId = registry.areaIdOf(entity.entityId);
      final String? home = areaId == null ? null : homeByArea[areaId];
      if (home == null || home.isEmpty) continue;
      final int score = (entity.currentTemperature != null ? 2 : 0) +
          (entity.currentHumidity != null ? 1 : 0);
      if (score == 0) continue;
      if (score > (scoreByHome[home] ?? 0)) {
        scoreByHome[home] = score;
        sourceByHome[home] = entity;
      }
    }

    return <HomeClimateSummary>[
      for (final String home in availableHomes)
        HomeClimateSummary(
          homeName: home,
          temperature: sourceByHome[home]?.currentTemperature,
          humidity: sourceByHome[home]?.currentHumidity,
          sourceName: sourceByHome[home]?.displayName,
        ),
    ];
  }

  /// 当前应展示的房间列表（受家庭筛选）。
  List<HaArea> get visibleAreas {    final String home = effectiveHomeName;
    if (home.isEmpty) return availableAreas;
    return availableAreas
        .where((HaArea area) => area.homeName == home)
        .toList(growable: false);
  }

  /// 可筛选家庭：含有任意实体的家庭，按注册表首次出现顺序；
  /// 未分配家庭的房间不参与家庭标签（仅在「全部」下可见）。
  List<String> get availableHomes {
    final List<String> homes = <String>[];
    for (final HaArea area in availableAreas) {
      final String home = area.homeName;
      if (home.isEmpty || homes.contains(home)) continue;
      homes.add(home);
    }
    return homes;
  }

  /// 家庭标签展示名。
  String homeLabel(String homeName) => homeName.isEmpty ? '未分配家庭' : homeName;

  /// 生效的家庭筛选：所选家庭失效时自动回退「全部」。
  String get effectiveHomeName =>
      availableHomes.contains(selectedHomeName) ? selectedHomeName : '';

  /// 生效的房间筛选：房间不在当前家庭/集合内时自动回退「全部」。
  String get effectiveAreaId {
    if (selectedAreaId.isEmpty) return '';
    for (final HaArea area in visibleAreas) {
      if (area.areaId == selectedAreaId) return selectedAreaId;
    }
    return '';
  }

  /// 某房间内的设备卡数量（房间标签上的角标，与网格卡片数一致）。
  int areaCount(String areaId) => _areaDeviceCounts[areaId] ?? 0;

  /// 某家庭内设备卡数量（家庭标签上的角标）。
  int homeCount(String homeName) {
    int count = 0;
    for (final HaArea area in availableAreas) {
      if (area.homeName == homeName) count += areaCount(area.areaId);
    }
    return count;
  }

  /// 房间 id → 该房间的设备卡数量。
  ///
  /// 同设备多实体只计一次，归属房间取该组内首个已分配房间的实体
  /// （正常情况下同设备实体房间一致）。
  Map<String, int> get _areaDeviceCounts {
    final Map<String, String> areaByGroupKey = <String, String>{};
    for (final HaEntityStateModel e in entities.values) {
      final String? areaId = registry.areaIdOf(e.entityId);
      if (areaId == null) continue;
      final String groupKey =
          registry.deviceIdOf(e.entityId) ?? 'entity:${e.entityId}';
      areaByGroupKey.putIfAbsent(groupKey, () => areaId);
    }
    final Map<String, int> counts = <String, int>{};
    for (final String areaId in areaByGroupKey.values) {
      counts[areaId] = (counts[areaId] ?? 0) + 1;
    }
    return counts;
  }

  /// 实体的房间展示名：选中家庭时用短房间名，否则用完整区域名；
  /// 未分配房间时给出兜底文案。
  String areaLabelFor(String entityId) {
    final String? areaId = registry.areaIdOf(entityId);
    if (areaId == null) return '未分配房间';
    for (final HaArea area in registry.areas) {
      if (area.areaId == areaId) {
        return area.roomName.isNotEmpty ? area.roomName : area.name;
      }
    }
    return '未分配房间';
  }

  /// 快捷控件列表：按家庭 + 房间两级筛选，light 在前、switch 在后，
  /// 按显示名排序。
  List<HaEntityStateModel> get quickControls {
    final List<HaEntityStateModel> list =
        _filteredSwitchable.values.toList(growable: false);
    list.sort((HaEntityStateModel a, HaEntityStateModel b) {
      final int byDomain =
          _domainWeight(a.domain).compareTo(_domainWeight(b.domain));
      if (byDomain != 0) return byDomain;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  /// 快捷列表域顺序：灯 → 空调 → 热水器 → 开关
  static int _domainWeight(String domain) => switch (domain) {
        'light' => 0,
        'climate' => 1,
        'water_heater' => 2,
        'switch' => 3,
        _ => 4,
      };

  /// 设备分组列表：同一物理设备的全部实体合并为一张卡片，供网格展示
  /// （家庭 ▸ 房间筛选；不过滤 domain，数据/动作类也显示）。
  List<HaDeviceGroup> get deviceGroups => HaDeviceGroup.group(
        entities: _filteredEntities,
        deviceIdOf: registry.deviceIdOf,
        deviceNameOf: (String deviceId) => registry.devices[deviceId]?.name,
      );

  /// 洗衣机设备摘要：device_id → 摘要（非洗衣机设备不出现）。
  ///
  /// 需要该设备的全部实体（switch/select/sensor/button），不能只用
  /// 可控实体，否则拿不到状态、模式和启动按钮。
  Map<String, WasherSummary> get washerSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, WasherSummary> result = <String, WasherSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final WasherSummary? summary = WasherSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 热水器设备摘要：device_id → 摘要（非热水器设备不出现）。
  Map<String, WaterHeaterSummary> get waterHeaterSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, WaterHeaterSummary> result =
        <String, WaterHeaterSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final WaterHeaterSummary? summary = WaterHeaterSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 电热水瓶摘要：device_id → 摘要（非热水瓶设备不出现）。
  Map<String, KettleSummary> get kettleSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, KettleSummary> result = <String, KettleSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final KettleSummary? summary = KettleSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 风扇摘要：device_id → 摘要（非风扇设备不出现）。
  Map<String, FanSummary> get fanSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, FanSummary> result = <String, FanSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final FanSummary? summary = FanSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 门锁摘要：device_id → 摘要（非门锁设备不出现）。
  Map<String, LockSummary> get lockSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, LockSummary> result = <String, LockSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 设备用电信息：device_id → PowerStats（没有功耗实体的设备不出现）。
  Map<String, PowerStats> get powerStats {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, PowerStats> result = <String, PowerStats>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final PowerStats? stats = PowerStats.tryBuild(list);
      if (stats != null) result[deviceId] = stats;
    });
    return result;
  }

  /// 油烟机摘要：device_id → 摘要（非油烟机不出现）。
  Map<String, RangeHoodSummary> get rangeHoodSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, RangeHoodSummary> result =
        <String, RangeHoodSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final RangeHoodSummary? summary = RangeHoodSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 净水器摘要：device_id → 摘要（非净水器不出现）。
  Map<String, WaterPurifierSummary> get waterPurifierSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, WaterPurifierSummary> result =
        <String, WaterPurifierSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final WaterPurifierSummary? summary = WaterPurifierSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 电饭煲摘要：device_id → 摘要（非电饭煲不出现）。
  Map<String, RiceCookerSummary> get riceCookerSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, RiceCookerSummary> result =
        <String, RiceCookerSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final RiceCookerSummary? summary = RiceCookerSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 空气炸锅摘要：device_id → 摘要（非空气炸锅不出现）。
  Map<String, AirFryerSummary> get airFryerSummaries {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, AirFryerSummary> result = <String, AirFryerSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final AirFryerSummary? summary = AirFryerSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 双开开关摘要：device_id → 摘要（没有两路 `_on_p_2_1` / `_on_p_3_1`
  /// 的设备不出现）。
  Map<String, MultiSwitchSummary> get multiSwitchSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, MultiSwitchSummary> result =
        <String, MultiSwitchSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final MultiSwitchSummary? summary = MultiSwitchSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 智能插座摘要：device_id → 摘要（非智能插座不出现）。
  Map<String, SocketSummary> get socketSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, SocketSummary> result = <String, SocketSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 冰箱摘要：device_id → 摘要（非冰箱设备不出现）。
  Map<String, FridgeSummary> get fridgeSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, FridgeSummary> result = <String, FridgeSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final FridgeSummary? summary = FridgeSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 投影仪摘要：device_id → 摘要（非投影仪设备不出现）。
  Map<String, ProjectorSummary> get projectorSummaries {    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in entities.values) {
      final String? deviceId = registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      byDevice
          .putIfAbsent(deviceId, () => <HaEntityStateModel>[])
          .add(entity);
    }

    final Map<String, ProjectorSummary> result =
        <String, ProjectorSummary>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> list) {
      final ProjectorSummary? summary = ProjectorSummary.tryBuild(
        deviceId: deviceId,
        name: registry.devices[deviceId]?.name ?? list.first.displayName,
        entities: list,
      );
      if (summary != null) result[deviceId] = summary;
    });
    return result;
  }

  /// 指定设备的分组（详情页用，不受家庭/房间筛选影响，含全部实体）；
  /// 不存在返回 null。
  HaDeviceGroup? deviceGroupOf(String deviceId) {
    for (final HaDeviceGroup group in HaDeviceGroup.group(
      entities: entities,
      deviceIdOf: registry.deviceIdOf,
      deviceNameOf: (String id) => registry.devices[id]?.name,
    )) {
      if (group.deviceId == deviceId) return group;
    }
    return null;
  }

  /// 按家庭 + 房间两级筛选后的可控实体表（key 为 entity_id）。
  Map<String, HaEntityStateModel> get _filteredSwitchable {
    final String home = effectiveHomeName;
    final String areaId = effectiveAreaId;
    final Set<String> allowedAreaIds = <String>{};
    if (areaId.isNotEmpty) {
      allowedAreaIds.add(areaId);
    } else if (home.isNotEmpty) {
      for (final HaArea area in availableAreas) {
        if (area.homeName == home) allowedAreaIds.add(area.areaId);
      }
    }
    return <String, HaEntityStateModel>{
      for (final HaEntityStateModel e in entities.values)
        if (e.isSwitchable &&
            (allowedAreaIds.isEmpty ||
            allowedAreaIds.contains(registry.areaIdOf(e.entityId))))
          e.entityId: e,
    };
  }

  /// 按家庭 + 房间两级筛选后的全部实体表（不过滤 domain / 可用性）。
  Map<String, HaEntityStateModel> get _filteredEntities {
    final String home = effectiveHomeName;
    final String areaId = effectiveAreaId;
    final Set<String> allowedAreaIds = <String>{};
    if (areaId.isNotEmpty) {
      allowedAreaIds.add(areaId);
    } else if (home.isNotEmpty) {
      for (final HaArea area in availableAreas) {
        if (area.homeName == home) allowedAreaIds.add(area.areaId);
      }
    }
    return <String, HaEntityStateModel>{
      for (final HaEntityStateModel e in entities.values)
        if (allowedAreaIds.isEmpty ||
            allowedAreaIds.contains(registry.areaIdOf(e.entityId)))
          e.entityId: e,
    };
  }

  HomeState copyWith({
    bool? isLoading,
    Map<String, HaEntityStateModel>? entities,
    Set<String>? togglingIds,
    HaRegistry? registry,
    String? selectedHomeName,
    String? selectedAreaId,
    String? errorMessage,
    NetErrorType? errorType,
    bool clearError = false,
  }) {
    return HomeState._(
      isLoading: isLoading ?? this.isLoading,
      entities: entities ?? this.entities,
      togglingIds: togglingIds ?? this.togglingIds,
      registry: registry ?? this.registry,
      selectedHomeName: selectedHomeName ?? this.selectedHomeName,
      selectedAreaId: selectedAreaId ?? this.selectedAreaId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
    );
  }
}

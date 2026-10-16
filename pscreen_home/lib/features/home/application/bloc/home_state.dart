import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';

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

  /// 可筛选的房间：仅含有可控实体的房间，保持注册表顺序。
  List<HaArea> get availableAreas {
    final Set<String> areaIds = <String>{};
    for (final HaEntityStateModel entity in entities.values) {
      if (!entity.isSwitchable) continue;
      final String? areaId = registry.areaIdOf(entity.entityId);
      if (areaId != null) areaIds.add(areaId);
    }
    return registry.areas
        .where((HaArea area) => areaIds.contains(area.areaId))
        .toList(growable: false);
  }

  /// 当前应展示的房间列表（受家庭筛选）。
  List<HaArea> get visibleAreas {
    final String home = effectiveHomeName;
    if (home.isEmpty) return availableAreas;
    return availableAreas
        .where((HaArea area) => area.homeName == home)
        .toList(growable: false);
  }

  /// 可筛选家庭：仅含有可控实体的家庭，按注册表首次出现顺序；
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

  /// 某房间内可控实体数量（房间标签上的角标）。
  int areaCount(String areaId) {
    int count = 0;
    for (final HaEntityStateModel entity in entities.values) {
      if (entity.isSwitchable && registry.areaIdOf(entity.entityId) == areaId) {
        count++;
      }
    }
    return count;
  }

  /// 某家庭内可控实体数量（家庭标签上的角标）。
  int homeCount(String homeName) {
    int count = 0;
    for (final HaArea area in availableAreas) {
      if (area.homeName == homeName) count += areaCount(area.areaId);
    }
    return count;
  }

  /// 实体的房间展示名：选中家庭时用短房间名，否则用完整区域名；
  /// 未分配房间时给出兜底文案。
  String areaLabelFor(String entityId) {
    final String? areaId = registry.areaIdOf(entityId);
    if (areaId == null) return '未分配房间';
    for (final HaArea area in registry.areas) {
      if (area.areaId == areaId) {
        return effectiveHomeName.isEmpty ? area.name : area.roomName;
      }
    }
    return '未分配房间';
  }

  /// 快捷控件列表：按家庭 + 房间两级筛选，light 在前、switch 在后，
  /// 按显示名排序。
  List<HaEntityStateModel> get quickControls {
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
    final List<HaEntityStateModel> list = entities.values
        .where((HaEntityStateModel e) =>
            e.isSwitchable &&
            (allowedAreaIds.isEmpty ||
                allowedAreaIds.contains(registry.areaIdOf(e.entityId))))
        .toList(growable: false);
    list.sort((HaEntityStateModel a, HaEntityStateModel b) {
      final int byDomain = a.domain.compareTo(b.domain);
      if (byDomain != 0) return byDomain;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
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

import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';

/// 主页状态（不可变，通过 copyWith 更新）。
class HomeState {
  const HomeState._({
    required this.isLoading,
    required this.entities,
    required this.togglingIds,
    required this.registry,
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

  /// 生效的房间筛选：所选房间失效（设备改归属/不可用）时自动回退「全部」。
  String get effectiveAreaId {
    if (selectedAreaId.isEmpty) return '';
    for (final HaArea area in availableAreas) {
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

  /// 实体的房间展示名（未分配房间时给出兜底文案）。
  String areaLabelFor(String entityId) =>
      registry.areaNameOf(entityId) ?? '未分配房间';

  /// 快捷控件列表：按选中房间过滤，light 在前、switch 在后，按显示名排序。
  List<HaEntityStateModel> get quickControls {
    final String areaId = effectiveAreaId;
    final List<HaEntityStateModel> list = entities.values
        .where((HaEntityStateModel e) =>
            e.isSwitchable &&
            (areaId.isEmpty || registry.areaIdOf(e.entityId) == areaId))
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
      selectedAreaId: selectedAreaId ?? this.selectedAreaId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
    );
  }
}

import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 主页状态（不可变，通过 copyWith 更新）。
class HomeState {
  const HomeState._({
    required this.isLoading,
    required this.entities,
    required this.togglingIds,
    this.errorMessage,
    this.errorType,
  });

  /// 初始状态。
  factory HomeState.initial() => const HomeState._(
        isLoading: false,
        entities: <String, HaEntityStateModel>{},
        togglingIds: <String>{},
        errorMessage: null,
        errorType: null,
      );

  final bool isLoading;

  /// 全部实体状态，key 为 entity_id
  final Map<String, HaEntityStateModel> entities;

  /// 正在执行开关指令的实体 id（卡片显示 loading）
  final Set<String> togglingIds;

  final String? errorMessage;
  final NetErrorType? errorType;

  /// 快捷控件列表：light 在前、switch 在后，按显示名排序。
  List<HaEntityStateModel> get quickControls {
    final List<HaEntityStateModel> list = entities.values
        .where((e) => e.isSwitchable)
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
    String? errorMessage,
    NetErrorType? errorType,
    bool clearError = false,
  }) {
    return HomeState._(
      isLoading: isLoading ?? this.isLoading,
      entities: entities ?? this.entities,
      togglingIds: togglingIds ?? this.togglingIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
    );
  }
}

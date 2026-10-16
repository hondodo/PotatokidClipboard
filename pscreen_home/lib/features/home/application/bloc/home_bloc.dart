import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/core/utils/bloc_event.dart';
import 'package:pscreen_home/core/utils/error_message.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页状态机：加载实体状态 → 订阅实时变更 → 响应快捷控件操作。
///
/// - [LoadHome]：连接就绪后拉取全量状态（重连成功会再次触发）；
/// - [EntityStateChanged]：WS 推送的单实体状态更新；
/// - [ToggleEntity]：乐观更新 + 失败回滚。
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({required this._repository})
      : super(HomeState.initial()) {
    on<LoadHome>(_onLoadHome);
    on<EntityStateChanged>(_onEntityStateChanged);
    on<ToggleEntity>(_onToggleEntity);
    on<HomeSelected>(_onHomeSelected);
    on<AreaSelected>(_onAreaSelected);
    on<ClearHomeError>(_onClearHomeError);
    _subscription = _repository.watchStateChanges().listen(
          (entity) => add(EntityStateChanged(entity)),
          onError: (Object e) =>
              Injection.get<LogService>().warn('状态订阅流异常：$e'),
        );
  }

  final HomeRepository _repository;
  StreamSubscription<HaEntityStateModel>? _subscription;

  Future<void> _onLoadHome(
    LoadHome event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      // 状态与注册表并行拉取；注册表失败由 Repository 降级为空，不阻断加载
      final List<Object> results = await Future.wait(<Future<Object>>[
        _repository.fetchStates(),
        _repository.fetchRegistry(),
      ]);
      final List<HaEntityStateModel> states =
          results[0] as List<HaEntityStateModel>;
      final HaRegistry registry = results[1] as HaRegistry;
      // 所选家庭/房间若已不存在（改归属 / 消失），回退「全部」
      String selectedHome = state.selectedHomeName;
      String selectedArea = state.selectedAreaId;
      if (selectedHome.isNotEmpty &&
          !registry.areas.any((HaArea a) => a.homeName == selectedHome)) {
        selectedHome = '';
        selectedArea = '';
      }
      if (selectedArea.isNotEmpty &&
          !registry.areas.any((HaArea a) => a.areaId == selectedArea)) {
        selectedArea = '';
      }
      emit(state.copyWith(
        isLoading: false,
        entities: <String, HaEntityStateModel>{
          for (final HaEntityStateModel s in states) s.entityId: s,
        },
        registry: registry,
        selectedHomeName: selectedHome,
        selectedAreaId: selectedArea,
      ));
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载实体状态失败', error: e, stackTrace: s);
      emit(state.copyWith(
        isLoading: false,
        errorMessage: mapErrorToMessage(e),
        errorType: e.toNetErrorType(),
      ));
      completeBlocEvent(event.completer, success: false);
    }
  }

  void _onEntityStateChanged(
    EntityStateChanged event,
    Emitter<HomeState> emit,
  ) {
    // 仅更新已加载过的实体，避免加载前的推送把列表"打脏"
    if (!state.entities.containsKey(event.entity.entityId)) return;
    emit(state.copyWith(
      entities: <String, HaEntityStateModel>{
        ...state.entities,
        event.entity.entityId: event.entity,
      },
    ));
  }

  Future<void> _onToggleEntity(
    ToggleEntity event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isSwitchable) {
      completeBlocEvent(event.completer, success: false);
      return;
    }

    final bool turnOn = !current.isOn;
    // 乐观更新：先翻转本地状态，指令成功后由 state_changed 事件校准
    emit(state.copyWith(
      entities: <String, HaEntityStateModel>{
        ...state.entities,
        event.entityId: current.copyWith(state: turnOn ? 'on' : 'off'),
      },
      togglingIds: <String>{...state.togglingIds, event.entityId},
      clearError: true,
    ));

    try {
      await _repository.setEntityPower(
        entityId: event.entityId,
        turnOn: turnOn,
      );
      emit(state.copyWith(
        togglingIds: <String>{...state.togglingIds}..remove(event.entityId),
      ));
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('开关控制失败：${event.entityId}',
          error: e, stackTrace: s);
      // 失败回滚到切换前的状态
      emit(state.copyWith(
        entities: <String, HaEntityStateModel>{
          ...state.entities,
          event.entityId: current,
        },
        togglingIds: <String>{...state.togglingIds}..remove(event.entityId),
        errorMessage: mapErrorToMessage(e),
        errorType: e.toNetErrorType(),
      ));
      completeBlocEvent(event.completer, success: false);
    }
  }

  void _onHomeSelected(
    HomeSelected event,
    Emitter<HomeState> emit,
  ) {
    // 切换家庭后房间行会重新计算，清空已选房间避免无效筛选
    emit(state.copyWith(
      selectedHomeName: event.homeName,
      selectedAreaId: '',
    ));
  }

  void _onAreaSelected(
    AreaSelected event,
    Emitter<HomeState> emit,
  ) {
    emit(state.copyWith(selectedAreaId: event.areaId));
  }

  void _onClearHomeError(
    ClearHomeError event,
    Emitter<HomeState> emit,
  ) {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

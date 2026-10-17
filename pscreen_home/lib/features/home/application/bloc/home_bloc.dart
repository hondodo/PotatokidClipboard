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
    on<SetLightBrightness>(_onSetLightBrightness);
    on<SetLightColorTemperature>(_onSetLightColorTemperature);
    on<SetLightEffect>(_onSetLightEffect);
    on<SetClimateTemperature>(_onSetClimateTemperature);
    on<SetClimateHvacMode>(_onSetClimateHvacMode);
    on<SetClimateFanMode>(_onSetClimateFanMode);
    on<SetClimateSwingMode>(_onSetClimateSwingMode);
    on<PressEntityButton>(_onPressEntityButton);
    on<SelectEntityOption>(_onSelectEntityOption);
    on<SetWaterHeaterTemperature>(_onSetWaterHeaterTemperature);
    on<SetWaterHeaterOperationMode>(_onSetWaterHeaterOperationMode);
    on<SetTextEntityValue>(_onSetTextEntityValue);
    on<SetNumberEntityValue>(_onSetNumberEntityValue);
    on<PressNotifyAction>(_onPressNotifyAction);
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
    // 乐观更新：先翻转本地状态，指令成功后由 state_changed 事件校准。
    // climate 的 state 是运行模式，不能写 'on'，按支持列表取一个默认模式。
    final String optimisticState;
    if (current.isClimate || current.isWaterHeater) {
      if (!turnOn) {
        optimisticState = 'off';
      } else {
        final List<String> modes = current.isWaterHeater
            ? current.operationModes
                .where((String m) => m != 'off')
                .toList()
            : current.hvacModes
                .where((String m) => m != 'off')
                .toList();
        if (current.isWaterHeater && modes.contains('自定义')) {
          optimisticState = '自定义';
        } else {
          optimisticState = modes.contains('auto')
              ? 'auto'
              : (modes.isNotEmpty ? modes.first : 'cool');
        }
      }
    } else {
      optimisticState = turnOn ? 'on' : 'off';
    }
    emit(state.copyWith(
      entities: <String, HaEntityStateModel>{
        ...state.entities,
        event.entityId: current.copyWith(state: optimisticState),
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

  // ------------------------------------------------------------ 参数控制

  Future<void> _onSetLightBrightness(
    SetLightBrightness event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isLight || !current.supportsBrightness) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final int percent = event.percent.clamp(1, 100).toInt();
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current
          .mergeAttributes(<String, dynamic>{
            'brightness': (percent * 255 / 100).round(),
          })
          .copyWith(state: 'on'),
      action: () => _repository.setLightBrightness(
        entityId: current.entityId,
        percent: percent,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetLightColorTemperature(
    SetLightColorTemperature event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isLight ||
        !current.supportsColorTemperature) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final int kelvin = event.kelvin
        .clamp(current.minColorTempKelvin!, current.maxColorTempKelvin!)
        .toInt();
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current
          .mergeAttributes(<String, dynamic>{
            'color_temp_kelvin': kelvin,
          })
          .copyWith(state: 'on'),
      action: () => _repository.setLightColorTemperature(
        entityId: current.entityId,
        kelvin: kelvin,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetLightEffect(
    SetLightEffect event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isLight ||
        !current.effectList.contains(event.effect)) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current
          .mergeAttributes(<String, dynamic>{
            'effect': event.effect,
          })
          .copyWith(state: 'on'),
      action: () => _repository.setLightEffect(
        entityId: current.entityId,
        effect: event.effect,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateTemperature(
    SetClimateTemperature event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isClimate) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final double step = current.targetTempStep;
    final double clamped = event.temperature
        .clamp(current.minTargetTemperature, current.maxTargetTemperature)
        .toDouble();
    final double temperature = (clamped / step).round() * step;
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'temperature': temperature,
      }),
      action: () => _repository.setClimateTemperature(
        entityId: current.entityId,
        temperature: temperature,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateHvacMode(
    SetClimateHvacMode event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isClimate ||
        (event.mode != 'off' && !current.hvacModes.contains(event.mode))) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.mode),
      action: () => _repository.setClimateHvacMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateFanMode(
    SetClimateFanMode event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isClimate ||
        !current.fanModes.contains(event.mode)) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'fan_mode': event.mode,
      }),
      action: () => _repository.setClimateFanMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateSwingMode(
    SetClimateSwingMode event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isClimate ||
        !current.swingModes.contains(event.mode)) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'swing_mode': event.mode,
      }),
      action: () => _repository.setClimateSwingMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onPressEntityButton(
    PressEntityButton event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'button' ||
        current.state == 'unavailable') {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    try {
      await _repository.pressButton(entityId: current.entityId);
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        '按钮操作失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(state.copyWith(
        errorMessage: mapErrorToMessage(e),
        errorType: e.toNetErrorType(),
      ));
      completeBlocEvent(event.completer, success: false);
    }
  }

  Future<void> _onSelectEntityOption(
    SelectEntityOption event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'select' ||
        !current.isAvailable ||
        !current.options.contains(event.option)) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.option),
      action: () => _repository.selectOption(
        entityId: current.entityId,
        option: event.option,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetWaterHeaterTemperature(
    SetWaterHeaterTemperature event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isWaterHeater) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final double step = current.targetTempStep;
    final double clamped = event.temperature
        .clamp(current.minTargetTemperature, current.maxTargetTemperature)
        .toDouble();
    final double temperature = (clamped / step).round() * step;
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'temperature': temperature,
      }),
      action: () => _repository.setWaterHeaterTemperature(
        entityId: current.entityId,
        temperature: temperature,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetWaterHeaterOperationMode(
    SetWaterHeaterOperationMode event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isWaterHeater ||
        (event.mode != 'off' &&
            !current.operationModes.contains(event.mode))) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.mode),
      action: () => _repository.setWaterHeaterOperationMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetTextEntityValue(
    SetTextEntityValue event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'text' ||
        !current.isAvailable) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.value),
      action: () => _repository.setTextValue(
        entityId: current.entityId,
        value: event.value,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetNumberEntityValue(
    SetNumberEntityValue event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'number' ||
        !current.isAvailable) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final String text = event.value == event.value.roundToDouble()
        ? event.value.toStringAsFixed(0)
        : event.value.toString();
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: text),
      action: () => _repository.setNumberValue(
        entityId: current.entityId,
        value: event.value,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onPressNotifyAction(
    PressNotifyAction event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'notify' ||
        current.state == 'unavailable') {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    try {
      await _repository.pressNotifyAction(entityId: current.entityId);
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        'notify 动作执行失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(state.copyWith(
        errorMessage: mapErrorToMessage(e),
        errorType: e.toNetErrorType(),
      ));
      completeBlocEvent(event.completer, success: false);
    }
  }

  /// 乐观更新单个实体属性，失败时回滚并写入错误。
  Future<void> _applyEntityPatch({
    required Emitter<HomeState> emit,
    required HaEntityStateModel current,
    required HaEntityStateModel patched,
    required Future<void> Function() action,
    Completer<bool>? completer,
  }) async {
    emit(state.copyWith(
      entities: <String, HaEntityStateModel>{
        ...state.entities,
        current.entityId: patched,
      },
      clearError: true,
    ));
    try {
      await action();
      completeBlocEvent(completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        '设备参数控制失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(state.copyWith(
        entities: <String, HaEntityStateModel>{
          ...state.entities,
          current.entityId: current,
        },
        errorMessage: mapErrorToMessage(e),
        errorType: e.toNetErrorType(),
      ));
      completeBlocEvent(completer, success: false);
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

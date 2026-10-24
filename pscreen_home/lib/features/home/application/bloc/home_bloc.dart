import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_net_exceptions.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_screen/core/utils/bloc_event.dart';
import 'package:pscreen_home/core/utils/ha_error_message.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/application/card_order_planner.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页状态机：加载实体状态 → 订阅实时变更 → 响应快捷控件操作。
///
/// - [LoadHome]：连接就绪后拉取全量状态（重连成功会再次触发）；
/// - [EntityStateChanged]：WS 推送的单实体状态更新；
/// - [ToggleEntity]：乐观更新 + 失败回滚。
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required this.repository,
    required MetricSampler sampler,
    SettingsStore? settingsStore,
  }) : _sampler = sampler,
       _settingsStore = settingsStore,
       // .env 指定了固定家庭时，进入主页即选中它（只显示该家庭的数据）。
       super(
         HomeState.initial().copyWith(
           selectedHomeName: HaConfig.pinnedHomeName,
           cardOrderAll: settingsStore?.cardOrderAll ?? const <String>[],
           cardOrderByHome:
               settingsStore?.cardOrderByHome ?? const <String, List<String>>{},
         ),
       ) {
    // 绑定指标采样源并启动：按配置间隔记录各设备最近 24 小时的曲线。
    _sampler.bind(_readMetricValues);
    on<LoadHome>(_onLoadHome);
    on<EntityStateChanged>(_onEntityStateChanged);
    on<ToggleEntity>(_onToggleEntity);
    on<HomeSelected>(_onHomeSelected);
    on<AreaSelected>(_onAreaSelected);
    on<ReorderCards>(_onReorderCards);
    on<SetLightBrightness>(_onSetLightBrightness);
    on<SetLightColorTemperature>(_onSetLightColorTemperature);
    on<SetLightEffect>(_onSetLightEffect);
    on<SetClimateTemperature>(_onSetClimateTemperature);
    on<SetClimateHvacMode>(_onSetClimateHvacMode);
    on<SetClimateFanMode>(_onSetClimateFanMode);
    on<SetClimateSwingMode>(_onSetClimateSwingMode);
    on<SetFanPresetMode>(_onSetFanPresetMode);
    on<SetFanPercentage>(_onSetFanPercentage);
    on<SetFanOscillating>(_onSetFanOscillating);
    on<PressEntityButton>(_onPressEntityButton);
    on<SelectEntityOption>(_onSelectEntityOption);
    on<SetWaterHeaterTemperature>(_onSetWaterHeaterTemperature);
    on<SetWaterHeaterOperationMode>(_onSetWaterHeaterOperationMode);
    on<SetTextEntityValue>(_onSetTextEntityValue);
    on<SetNumberEntityValue>(_onSetNumberEntityValue);
    on<PressNotifyAction>(_onPressNotifyAction);
    on<ClearHomeError>(_onClearHomeError);
    _subscription = repository.watchStateChanges().listen(
      (entity) => add(EntityStateChanged(entity)),
      onError: (Object e) => Injection.get<LogService>().warn('状态订阅流异常：$e'),
    );
  }

  final HomeRepository repository;
  final MetricSampler _sampler;
  final SettingsStore? _settingsStore;
  StreamSubscription<HaEntityStateModel>? _subscription;

  /// 采样源：device_id → metric → 当前数值（来自 HA 实时状态，不额外发请求）。
  ///
  /// 遍历全部实体（不受首页家庭/房间筛选影响），保证切换筛选后历史连贯。
  /// 温度 / 湿度优先取同设备数值型 sensor，没有时回退 climate 属性。
  Map<String, Map<Metric, double?>> _readMetricValues() {
    final Map<String, List<HaEntityStateModel>> byDevice =
        <String, List<HaEntityStateModel>>{};
    for (final HaEntityStateModel entity in state.entities.values) {
      final String? deviceId = state.registry.deviceIdOf(entity.entityId);
      if (deviceId == null) continue;
      (byDevice[deviceId] ??= <HaEntityStateModel>[]).add(entity);
    }

    final Map<String, Map<Metric, double?>> out =
        <String, Map<Metric, double?>>{};
    byDevice.forEach((String deviceId, List<HaEntityStateModel> entities) {
      final Map<Metric, MetricSource> sources =
          MetricEntityResolver.resolveEntities(entities);
      if (sources.isEmpty) return;
      out[deviceId] = <Metric, double?>{
        for (final MapEntry<Metric, MetricSource> entry in sources.entries)
          entry.key: state.entities[entry.value.entityId] == null
              ? null
              : entry.value.valueOf(state.entities[entry.value.entityId]!),
      };
    });
    return out;
  }

  Future<void> _onLoadHome(LoadHome event, Emitter<HomeState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      // 状态与注册表并行拉取；注册表失败由 Repository 回退本地缓存 / 空，
      // 不阻断加载。
      final List<Object> results = await Future.wait(<Future<Object>>[
        repository.fetchStates(),
        repository.fetchRegistry(),
      ]);
      final List<HaEntityStateModel> states =
          results[0] as List<HaEntityStateModel>;
      final HaRegistry registry = results[1] as HaRegistry;
      // .env 固定家庭优先于用户选择；未配置时沿用当前选择。
      final String pinnedHome = HaConfig.pinnedHomeName;
      // 所选家庭/房间若已不存在（改归属 / 消失），回退「全部」
      String selectedHome = pinnedHome.isNotEmpty
          ? pinnedHome
          : state.selectedHomeName;
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
      emit(
        state.copyWith(
          isLoading: false,
          entities: <String, HaEntityStateModel>{
            for (final HaEntityStateModel s in states) s.entityId: s,
          },
          registry: registry,
          selectedHomeName: selectedHome,
          selectedAreaId: selectedArea,
        ),
      );
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载实体状态失败', error: e, stackTrace: s);
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: mapHaErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
      completeBlocEvent(event.completer, success: false);
    }
  }

  void _onEntityStateChanged(
    EntityStateChanged event,
    Emitter<HomeState> emit,
  ) {
    // 仅更新已加载过的实体，避免加载前的推送把列表"打脏"
    if (!state.entities.containsKey(event.entity.entityId)) return;
    emit(
      state.copyWith(
        entities: <String, HaEntityStateModel>{
          ...state.entities,
          event.entity.entityId: event.entity,
        },
      ),
    );
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
            ? current.operationModes.where((String m) => m != 'off').toList()
            : current.hvacModes.where((String m) => m != 'off').toList();
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
    emit(
      state.copyWith(
        entities: <String, HaEntityStateModel>{
          ...state.entities,
          event.entityId: current.copyWith(state: optimisticState),
        },
        togglingIds: <String>{...state.togglingIds, event.entityId},
        clearError: true,
      ),
    );

    try {
      await repository.setEntityPower(entityId: event.entityId, turnOn: turnOn);
      emit(
        state.copyWith(
          togglingIds: <String>{...state.togglingIds}..remove(event.entityId),
        ),
      );
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        '开关控制失败：${event.entityId}',
        error: e,
        stackTrace: s,
      );
      // 失败回滚到切换前的状态
      emit(
        state.copyWith(
          entities: <String, HaEntityStateModel>{
            ...state.entities,
            event.entityId: current,
          },
          togglingIds: <String>{...state.togglingIds}..remove(event.entityId),
          errorMessage: mapHaErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
      completeBlocEvent(event.completer, success: false);
    }
  }

  void _onHomeSelected(HomeSelected event, Emitter<HomeState> emit) {
    // .env 固定家庭时忽略切换（概览条已隐藏，这里防御其他入口）。
    final String pinnedHome = HaConfig.pinnedHomeName;
    // 切换家庭后房间行会重新计算，清空已选房间避免无效筛选
    emit(
      state.copyWith(
        selectedHomeName: pinnedHome.isNotEmpty ? pinnedHome : event.homeName,
        selectedAreaId: '',
      ),
    );
  }

  void _onAreaSelected(AreaSelected event, Emitter<HomeState> emit) {
    emit(state.copyWith(selectedAreaId: event.areaId));
  }

  Future<void> _onReorderCards(
    ReorderCards event,
    Emitter<HomeState> emit,
  ) async {
    if (event.visibleKeys.isEmpty) return;

    final List<HaDeviceGroup> allGroups = state.allDeviceGroups;
    final List<String> allKeys = allGroups
        .map((HaDeviceGroup group) => group.orderKey)
        .toList(growable: false);
    final Map<String, String> homeByKey = <String, String>{
      for (final HaDeviceGroup group in allGroups)
        group.orderKey: state.homeNameForEntity(
          (group.primary ?? group.entities.first).entityId,
        ),
    };

    final CardOrderPlan plan = CardOrderPlanner.apply(
      allOrder: state.cardOrderAll,
      homeOrders: state.cardOrderByHome,
      allCurrentKeys: allKeys,
      homeByKey: homeByKey,
      viewHome: event.homeName,
      visibleNewOrder: event.visibleKeys,
    );

    emit(
      state.copyWith(
        cardOrderAll: plan.allOrder,
        cardOrderByHome: plan.homeOrders,
      ),
    );
    await _settingsStore?.saveCardOrders(
      all: plan.allOrder,
      byHome: plan.homeOrders,
    );
  }

  void _onClearHomeError(ClearHomeError event, Emitter<HomeState> emit) {
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
      action: () => repository.setLightBrightness(
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
          .mergeAttributes(<String, dynamic>{'color_temp_kelvin': kelvin})
          .copyWith(state: 'on'),
      action: () => repository.setLightColorTemperature(
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
          .mergeAttributes(<String, dynamic>{'effect': event.effect})
          .copyWith(state: 'on'),
      action: () => repository.setLightEffect(
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
      action: () => repository.setClimateTemperature(
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
      action: () => repository.setClimateHvacMode(
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
      action: () => repository.setClimateFanMode(
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
      action: () => repository.setClimateSwingMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetFanPresetMode(
    SetFanPresetMode event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        !current.isFan ||
        !current.presetModes.contains(event.mode)) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'preset_mode': event.mode,
      }),
      action: () => repository.setFanPresetMode(
        entityId: current.entityId,
        mode: event.mode,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetFanPercentage(
    SetFanPercentage event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isFan) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    final int percentage = event.percentage.clamp(0, 100).toInt();
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'percentage': percentage,
      }),
      action: () => repository.setFanPercentage(
        entityId: current.entityId,
        percentage: percentage,
      ),
      completer: event.completer,
    );
  }

  Future<void> _onSetFanOscillating(
    SetFanOscillating event,
    Emitter<HomeState> emit,
  ) async {
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null || !current.isFan) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.mergeAttributes(<String, dynamic>{
        'oscillating': event.oscillating,
      }),
      action: () => repository.setFanOscillating(
        entityId: current.entityId,
        oscillating: event.oscillating,
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
      await repository.pressButton(entityId: current.entityId);
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        '按钮操作失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          errorMessage: mapHaErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
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
      action: () => repository.selectOption(
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
      action: () => repository.setWaterHeaterTemperature(
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
        (event.mode != 'off' && !current.operationModes.contains(event.mode))) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.mode),
      action: () => repository.setWaterHeaterOperationMode(
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
    if (current == null || current.domain != 'text' || !current.isAvailable) {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    await _applyEntityPatch(
      emit: emit,
      current: current,
      patched: current.copyWith(state: event.value),
      action: () => repository.setTextValue(
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
    if (current == null || current.domain != 'number' || !current.isAvailable) {
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
      action: () => repository.setNumberValue(
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
      await repository.pressNotifyAction(
        entityId: current.entityId,
        message: event.message,
      );
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        'notify 动作执行失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          errorMessage: mapHaErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
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
    emit(
      state.copyWith(
        entities: <String, HaEntityStateModel>{
          ...state.entities,
          current.entityId: patched,
        },
        clearError: true,
      ),
    );
    try {
      await action();
      completeBlocEvent(completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error(
        '设备参数控制失败：${current.entityId}',
        error: e,
        stackTrace: s,
      );
      emit(
        state.copyWith(
          entities: <String, HaEntityStateModel>{
            ...state.entities,
            current.entityId: current,
          },
          errorMessage: mapHaErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
      completeBlocEvent(completer, success: false);
    }
  }

  @override
  Future<void> close() {
    _sampler.stop();
    _subscription?.cancel();
    return super.close();
  }
}

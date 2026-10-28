import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_connection_label.dart';
import 'package:pscreen_home/core/network/ha_net_exceptions.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_screen/core/utils/bloc_event.dart';
import 'package:pscreen_home/core/utils/ha_error_message.dart';
import 'package:pscreen_home/features/connection/domain/repositories/connection_repository.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/application/card_order_planner.dart';
import 'package:pscreen_home/features/home/application/ha_action_report.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_state_cache.dart';
import 'package:pscreen_home/features/home/domain/repositories/registry_cache.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

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
    List<Duration>? loadRetryDelays,
    HomeStateCache? stateCache,
    RegistryCache? registryCache,
    ConnectionRepository? connection,
    HaActionReporter? actionReporter,
    CurrentSceneProvider? sceneProvider,
  }) : _sampler = sampler,
       _settingsStore = settingsStore,
       _stateCache = stateCache,
       _registryCache = registryCache,
       _connection = connection,
       _actionReporter = actionReporter,
       _sceneProvider = sceneProvider,
       _loadRetryDelays =
           loadRetryDelays ??
           const <Duration>[
             Duration(seconds: 5),
             Duration(seconds: 10),
             Duration(seconds: 30),
           ],
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
    on<RestoreCachedHome>(_onRestoreCachedHome);
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
    // 冷启动先用本地快照渲染卡片，连接就绪后的 LoadHome 再校准。
    add(const RestoreCachedHome());
  }

  final HomeRepository repository;
  final MetricSampler _sampler;
  final SettingsStore? _settingsStore;
  final HomeStateCache? _stateCache;
  final RegistryCache? _registryCache;
  final ConnectionRepository? _connection;
  final HaActionReporter? _actionReporter;
  final CurrentSceneProvider? _sceneProvider;
  final List<Duration> _loadRetryDelays;
  StreamSubscription<HaEntityStateModel>? _subscription;
  Timer? _loadRetryTimer;
  int _loadRetryAttempt = 0;
  int _actionSeq = 0;

  /// 快照写入节流：重连可能很频繁，序列化一千多个实体会卡一帧，
  /// 首次加载立即写，之后最多每 5 分钟刷新一次。
  static const Duration _cacheSaveInterval = Duration(minutes: 5);
  DateTime? _lastCacheSavedAt;

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

  /// 冷启动时恢复上次成功加载的实体快照。
  ///
  /// 有快照就先展示卡片（右上角仍显示真实连接状态），连接就绪后
  /// 页面会派发 [LoadHome] 用在线数据覆盖；没有注册表时不恢复：
  /// 上千个实体各自成卡会让首页卡死，等全量加载更安全。
  Future<void> _onRestoreCachedHome(
    RestoreCachedHome event,
    Emitter<HomeState> emit,
  ) async {
    final HomeStateCache? cache = _stateCache;
    if (cache == null) return;
    try {
      final List<HaEntityStateModel>? cached = await cache.read();
      if (cached == null || cached.isEmpty) return;
      if (isClosed || state.hasLoaded || state.isLoading) return;
      final HaRegistry registry = _registryCache?.read() ?? HaRegistry.empty;
      if (registry.areas.isEmpty && registry.devices.isEmpty) {
        Injection.get<LogService>().debug('实体快照缺少注册表，跳过恢复');
        return;
      }
      String selectedHome = state.selectedHomeName;
      if (selectedHome.isNotEmpty &&
          !registry.areas.any((HaArea area) => area.homeName == selectedHome)) {
        selectedHome = '';
      }
      emit(
        state.copyWith(
          isLoading: false,
          hasLoaded: true,
          isFromCache: true,
          entities: <String, HaEntityStateModel>{
            for (final HaEntityStateModel entity in cached)
              entity.entityId: entity,
          },
          registry: registry,
          selectedHomeName: selectedHome,
          selectedAreaId: '',
          loadedAt: DateTime.now(),
          clearError: true,
        ),
      );
      Injection.get<LogService>().debug('已从本地快照恢复 ${cached.length} 个实体');
    } catch (e) {
      Injection.get<LogService>().warn('恢复本地实体快照失败：$e');
    }
  }

  /// 全量加载成功后异步刷新快照；失败不影响本次展示。
  void _saveStates(List<HaEntityStateModel> states) {
    final HomeStateCache? cache = _stateCache;
    if (cache == null || states.isEmpty) return;
    final DateTime now = DateTime.now();
    final DateTime? last = _lastCacheSavedAt;
    if (last != null && now.difference(last) < _cacheSaveInterval) return;
    _lastCacheSavedAt = now;
    unawaited(cache.write(states));
  }

  /// 非「已连接」时拦截所有会下发到 HA 的控制操作。
  ///
  /// 统一在状态机入口拦截，卡片 / 详情页 / 弹窗的所有控件都覆盖；
  /// 卡片跳转详情不经过这里，因此断线时仍可浏览。
  bool _blockHaInteraction(
    Completer<bool>? completer,
    Emitter<HomeState> emit,
  ) {
    final ConnectionRepository? connection = _connection;
    if (connection == null) return false;
    final HaConnectionInfo info = connection.current;
    if (info.isReady) return false;
    final String message = haInteractionBlockedMessage(
      info.phase,
      retryCount: info.retryCount,
    );
    if (state.errorMessage != message) {
      emit(state.copyWith(errorMessage: message));
    }
    completeBlocEvent(completer, success: false);
    return true;
  }

  Future<void> _onLoadHome(LoadHome event, Emitter<HomeState> emit) async {
    _loadRetryTimer?.cancel();
    _loadRetryTimer = null;
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
      // HA 重启时 WebSocket API 可能先于实体平台就绪，`get_states` 会成功
      // 返回空列表。这不能当成「家里确实没有设备」：保留已有卡片并自动
      // 重试，否则页面会停在「没有找到实体」且再也没有恢复入口。
      if (states.isEmpty) {
        const String message = '暂时没有获取到设备（Home Assistant 可能正在启动），正在自动重试…';
        Injection.get<LogService>().warn('get_states 返回空列表，保留现有数据并重试');
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: message,
            errorType: HaErrorType.requestError,
          ),
        );
        _scheduleLoadRetry();
        completeBlocEvent(event.completer, success: false);
        return;
      }
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
      _loadRetryAttempt = 0;
      emit(
        state.copyWith(
          isLoading: false,
          hasLoaded: true,
          isFromCache: false,
          entities: <String, HaEntityStateModel>{
            for (final HaEntityStateModel s in states) s.entityId: s,
          },
          registry: registry,
          selectedHomeName: selectedHome,
          selectedAreaId: selectedArea,
          loadedAt: DateTime.now(),
        ),
      );
      _saveStates(states);
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载实体状态失败', error: e, stackTrace: s);
      final HaErrorType errorType = e.toNetErrorType();
      // 已有在线数据时保留旧卡片，只提示错误，不自动重试；
      // 只有「从未成功加载」或「当前展示的是本地快照」才重试，
      // 避免连接看似就绪但请求失败时一直停在旧快照上。
      final bool hasFreshData =
          state.hasLoaded && !state.isFromCache && state.entities.isNotEmpty;
      final bool shouldRetry =
          !hasFreshData &&
          errorType != HaErrorType.authError &&
          errorType != HaErrorType.dataError;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: mapHaErrorToMessage(e),
          errorType: errorType,
        ),
      );
      if (shouldRetry) _scheduleLoadRetry();
      completeBlocEvent(event.completer, success: false);
    }
  }

  /// 首次全量加载失败后的自动重试（5s / 10s / 30s，之后维持 30s）。
  ///
  /// 只有「还没有在线数据」（从未加载成功，或当前只有本地快照）时才重试；
  /// 已有在线卡片时保留旧数据，避免刷新失败把界面清空。连接恢复后页面的
  /// LoadHome 会取消这里的计时器。
  void _scheduleLoadRetry() {
    _loadRetryTimer?.cancel();
    if (_loadRetryDelays.isEmpty) return;
    final int index = _loadRetryAttempt.clamp(0, _loadRetryDelays.length - 1);
    final Duration delay = _loadRetryDelays[index];
    _loadRetryAttempt++;
    _loadRetryTimer = Timer(delay, () {
      if (isClosed) return;
      add(const LoadHome());
    });
  }

  void _onEntityStateChanged(
    EntityStateChanged event,
    Emitter<HomeState> emit,
  ) {
    // 加载完成前不接收推送，避免全量数据到达前把列表"打脏"；
    // 加载完成后允许补入未知实体：空/不完整加载（例如 HA 重启窗口内
    // 只拿到部分实体）可以靠后续 state_changed 自动补齐，不必等手动刷新。
    if (!state.hasLoaded) return;
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
    if (_blockHaInteraction(event.completer, emit)) return;
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
      _reportAction(
        entity: current,
        action: turnOn ? 'turn_on' : 'turn_off',
        success: true,
        value: turnOn ? 'on' : 'off',
        previousValue: current.state,
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
      _reportAction(
        entity: current,
        action: turnOn ? 'turn_on' : 'turn_off',
        success: false,
        value: turnOn ? 'on' : 'off',
        previousValue: current.state,
        error: mapHaErrorToMessage(e),
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
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_brightness',
      value: percent,
      previousValue: current.brightnessPercent,
      completer: event.completer,
    );
  }

  Future<void> _onSetLightColorTemperature(
    SetLightColorTemperature event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_color_temperature',
      value: kelvin,
      previousValue: current.colorTempKelvin,
      completer: event.completer,
    );
  }

  Future<void> _onSetLightEffect(
    SetLightEffect event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_effect',
      value: event.effect,
      previousValue: current.effect,
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateTemperature(
    SetClimateTemperature event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_temperature',
      value: temperature,
      previousValue: current.targetTemperature,
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateHvacMode(
    SetClimateHvacMode event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_hvac_mode',
      value: event.mode,
      previousValue: current.state,
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateFanMode(
    SetClimateFanMode event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_fan_mode',
      value: event.mode,
      previousValue: current.fanMode,
      completer: event.completer,
    );
  }

  Future<void> _onSetClimateSwingMode(
    SetClimateSwingMode event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_swing_mode',
      value: event.mode,
      previousValue: current.swingMode,
      completer: event.completer,
    );
  }

  Future<void> _onSetFanPresetMode(
    SetFanPresetMode event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_preset_mode',
      value: event.mode,
      previousValue: current.presetMode,
      completer: event.completer,
    );
  }

  Future<void> _onSetFanPercentage(
    SetFanPercentage event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_percentage',
      value: percentage,
      previousValue: current.fanPercentage,
      completer: event.completer,
    );
  }

  Future<void> _onSetFanOscillating(
    SetFanOscillating event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_oscillating',
      value: event.oscillating,
      previousValue: current.isOscillating,
      completer: event.completer,
    );
  }

  Future<void> _onPressEntityButton(
    PressEntityButton event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
    final HaEntityStateModel? current = state.entities[event.entityId];
    if (current == null ||
        current.domain != 'button' ||
        current.state == 'unavailable') {
      completeBlocEvent(event.completer, success: false);
      return;
    }
    try {
      await repository.pressButton(entityId: current.entityId);
      _reportAction(
        entity: current,
        action: 'press',
        success: true,
      );
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
      _reportAction(
        entity: current,
        action: 'press',
        success: false,
        error: mapHaErrorToMessage(e),
      );
      completeBlocEvent(event.completer, success: false);
    }
  }

  Future<void> _onSelectEntityOption(
    SelectEntityOption event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'select_option',
      value: event.option,
      previousValue: current.state,
      completer: event.completer,
    );
  }

  Future<void> _onSetWaterHeaterTemperature(
    SetWaterHeaterTemperature event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_temperature',
      value: temperature,
      previousValue: current.targetTemperature,
      completer: event.completer,
    );
  }

  Future<void> _onSetWaterHeaterOperationMode(
    SetWaterHeaterOperationMode event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_operation_mode',
      value: event.mode,
      previousValue: current.operationMode,
      completer: event.completer,
    );
  }

  Future<void> _onSetTextEntityValue(
    SetTextEntityValue event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_text',
      value: event.value,
      previousValue: current.state,
      completer: event.completer,
    );
  }

  Future<void> _onSetNumberEntityValue(
    SetNumberEntityValue event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      actionCode: 'set_number',
      value: event.value,
      previousValue: current.state,
      completer: event.completer,
    );
  }

  Future<void> _onPressNotifyAction(
    PressNotifyAction event,
    Emitter<HomeState> emit,
  ) async {
    if (_blockHaInteraction(event.completer, emit)) return;
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
      _reportAction(
        entity: current,
        action: 'notify',
        success: true,
        value: event.message,
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
      _reportAction(
        entity: current,
        action: 'notify',
        success: false,
        value: event.message,
        error: mapHaErrorToMessage(e),
      );
      completeBlocEvent(event.completer, success: false);
    }
  }

  /// 统一生成 HA 操作事件；没有注入上报器时静默跳过。
  ///
  /// 上报失败不能影响控制链路，因此这里吞掉采集/序列化异常。
  void _reportAction({
    required HaEntityStateModel entity,
    required String action,
    required bool success,
    Object? value,
    Object? previousValue,
    String? error,
    String? entityName,
    String? cardName,
    String? buttonId,
  }) {
    final HaActionReporter? reporter = _actionReporter;
    if (reporter == null) return;
    SceneSnapshot? scene;
    try {
      scene = _sceneProvider?.snapshot();
    } catch (_) {
      // 场景采集失败不影响 HA 操作本身的上报。
    }
    try {
      final DateTime now = DateTime.now();
      final String? deviceId = state.registry.deviceIdOf(entity.entityId);
      final String? areaId = state.registry.areaIdOf(entity.entityId);
      reporter.report(
        HaActionReport(
          eventId: '${now.microsecondsSinceEpoch}-${_actionSeq++}',
          at: now,
          action: action,
          entityId: entity.entityId,
          entityName: entityName ?? entity.displayName,
          deviceId: deviceId,
          deviceName:
              deviceId == null ? null : state.registry.devices[deviceId]?.name,
          areaId: areaId,
          areaName: areaId == null ? null : _areaNameOf(areaId),
          value: _trimReportValue(value),
          previousValue: _trimReportValue(previousValue),
          success: success,
          error: error,
          cardName: cardName,
          buttonId:
              buttonId ?? (action == 'press' ? entity.entityId : null),
          trigger: _actionTrigger(scene),
          scene: scene,
        ),
      );
    } catch (_) {
      // 上报不可用（例如通道未启动/序列化失败）时不打断控制。
    }
  }

  /// 卡片点击进入详情时调用；路由跳转本身不经过 HA，因此单独上报。
  void reportCardOpened(HaDeviceGroup group) {
    if (group.deviceId == null) return;
    final HaEntityStateModel entity = group.primary ?? group.entities.first;
    _reportAction(
      entity: entity,
      action: 'open_device_detail',
      success: true,
      value: group.title,
      entityName: group.title,
      cardName: group.title,
    );
  }

  String? _areaNameOf(String areaId) {
    for (final HaArea area in state.registry.areas) {
      if (area.areaId == areaId) return area.name;
    }
    return null;
  }

  String _actionTrigger(SceneSnapshot? scene) {
    if (scene == null) return 'unknown';
    if (scene.kind == SceneKind.deviceDetail) return 'device_detail';
    if (scene.kind == SceneKind.home) return 'home_card';
    return 'unknown';
  }

  /// 文本类设置值可能很长/含隐私内容，上报时截断。
  Object? _trimReportValue(Object? value) {
    if (value is String && value.length > 120) {
      return '${value.substring(0, 117)}...';
    }
    return value;
  }

  /// 乐观更新单个实体属性，失败时回滚并写入错误。
  Future<void> _applyEntityPatch({
    required Emitter<HomeState> emit,
    required HaEntityStateModel current,
    required HaEntityStateModel patched,
    required Future<void> Function() action,
    required String actionCode,
    Object? value,
    Object? previousValue,
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
      _reportAction(
        entity: current,
        action: actionCode,
        success: true,
        value: value,
        previousValue: previousValue,
      );
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
      _reportAction(
        entity: current,
        action: actionCode,
        success: false,
        value: value,
        previousValue: previousValue,
        error: mapHaErrorToMessage(e),
      );
      completeBlocEvent(completer, success: false);
    }
  }

  @override
  Future<void> close() {
    _loadRetryTimer?.cancel();
    _sampler.stop();
    _subscription?.cancel();
    return super.close();
  }
}

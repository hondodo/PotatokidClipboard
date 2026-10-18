import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/home_climate_summary.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_usage_record.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 内存版 HomeRepository：可控成功/失败，可注入实时状态事件
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({required this.states});

  List<HaEntityStateModel> states;
  HaRegistry registry = HaRegistry.empty;
  Object? fetchError;
  Object? toggleError;
  Object? controlError;
  final List<(String, bool)> toggleCalls = <(String, bool)>[];
  final List<(String, int)> brightnessCalls = <(String, int)>[];
  final List<(String, int)> colorTempCalls = <(String, int)>[];
  final List<(String, String)> effectCalls = <(String, String)>[];
  final List<(String, double)> climateTempCalls = <(String, double)>[];
  final List<(String, String)> hvacModeCalls = <(String, String)>[];
  final List<(String, String)> fanModeCalls = <(String, String)>[];
  final List<(String, String)> swingModeCalls = <(String, String)>[];
  final List<String> buttonCalls = <String>[];
  final List<(String, String)> selectCalls = <(String, String)>[];
  final List<(String, double)> waterHeaterTempCalls = <(String, double)>[];
  final List<(String, String)> waterHeaterModeCalls = <(String, String)>[];
  final List<(String, String)> textCalls = <(String, String)>[];
  final List<(String, double)> numberCalls = <(String, double)>[];
  final List<(String, String)> notifyCalls = <(String, String)>[];
  List<WaterUsageRecord> usageRecords = <WaterUsageRecord>[];
  final StreamController<HaEntityStateModel> _events =
      StreamController<HaEntityStateModel>.broadcast();

  @override
  Future<List<HaEntityStateModel>> fetchStates() async {
    if (fetchError != null) throw fetchError!;
    return states;
  }

  @override
  Future<HaRegistry> fetchRegistry() async => registry;

  @override
  Stream<HaEntityStateModel> watchStateChanges() => _events.stream;

  @override
  Future<void> setEntityPower({
    required String entityId,
    required bool turnOn,
  }) async {
    toggleCalls.add((entityId, turnOn));
    if (toggleError != null) throw toggleError!;
  }

  @override
  Future<void> setLightBrightness({
    required String entityId,
    required int percent,
  }) async {
    brightnessCalls.add((entityId, percent));
    _throwControlError();
  }

  @override
  Future<void> setLightColorTemperature({
    required String entityId,
    required int kelvin,
  }) async {
    colorTempCalls.add((entityId, kelvin));
    _throwControlError();
  }

  @override
  Future<void> setLightEffect({
    required String entityId,
    required String effect,
  }) async {
    effectCalls.add((entityId, effect));
    _throwControlError();
  }

  @override
  Future<void> setClimateTemperature({
    required String entityId,
    required double temperature,
  }) async {
    climateTempCalls.add((entityId, temperature));
    _throwControlError();
  }

  @override
  Future<void> setClimateHvacMode({
    required String entityId,
    required String mode,
  }) async {
    hvacModeCalls.add((entityId, mode));
    _throwControlError();
  }

  @override
  Future<void> setClimateFanMode({
    required String entityId,
    required String mode,
  }) async {
    fanModeCalls.add((entityId, mode));
    _throwControlError();
  }

  @override
  Future<void> setClimateSwingMode({
    required String entityId,
    required String mode,
  }) async {
    swingModeCalls.add((entityId, mode));
    _throwControlError();
  }

  @override
  Future<void> pressButton({required String entityId}) async {
    buttonCalls.add(entityId);
    _throwControlError();
  }

  @override
  Future<void> selectOption({
    required String entityId,
    required String option,
  }) async {
    selectCalls.add((entityId, option));
    _throwControlError();
  }

  @override
  Future<void> setWaterHeaterTemperature({
    required String entityId,
    required double temperature,
  }) async {
    waterHeaterTempCalls.add((entityId, temperature));
    _throwControlError();
  }

  @override
  Future<void> setWaterHeaterOperationMode({
    required String entityId,
    required String mode,
  }) async {
    waterHeaterModeCalls.add((entityId, mode));
    _throwControlError();
  }

  @override
  Future<List<WaterUsageRecord>> fetchWaterUsageRecords({
    required String entityId,
    required DateTime start,
    required DateTime end,
  }) async => usageRecords;

  @override
  Future<void> setTextValue({
    required String entityId,
    required String value,
  }) async {
    textCalls.add((entityId, value));
    _throwControlError();
  }

  @override
  Future<void> setNumberValue({
    required String entityId,
    required double value,
  }) async {
    numberCalls.add((entityId, value));
    _throwControlError();
  }

  @override
  Future<void> pressNotifyAction({
    required String entityId,
    required String message,
  }) async {
    notifyCalls.add((entityId, message));
    _throwControlError();
  }

  void _throwControlError() {
    if (controlError != null) throw controlError!;
  }

  void emitChange(HaEntityStateModel entity) => _events.add(entity);
}

HaEntityStateModel _entity(
  String entityId,
  String state, {
  Map<String, dynamic> attributes = const <String, dynamic>{},
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{
        'friendly_name': entityId,
        ...attributes,
      },
    );

Future<bool> _load(HomeBloc bloc) {
  final Completer<bool> completer = Completer<bool>();
  bloc.add(LoadHome(completer: completer));
  return completer.future.timeout(const Duration(seconds: 5));
}

Future<bool> _toggle(HomeBloc bloc, String entityId) {
  final Completer<bool> completer = Completer<bool>();
  bloc.add(ToggleEntity(entityId: entityId, completer: completer));
  return completer.future.timeout(const Duration(seconds: 5));
}

/// 派发带 completer 的事件并等待完成。
Future<bool> _run(
  HomeBloc bloc,
  void Function(Completer<bool> completer) dispatch,
) {
  final Completer<bool> completer = Completer<bool>();
  dispatch(completer);
  return completer.future.timeout(const Duration(seconds: 5));
}

const Map<String, dynamic> _lightAttributes = <String, dynamic>{
  'friendly_name': '卧室大灯',
  'brightness': 204,
  'color_temp_kelvin': 3500,
  'min_color_temp_kelvin': 2700,
  'max_color_temp_kelvin': 5700,
  'supported_color_modes': <String>['color_temp'],
  'effect_list': <String>['明亮模式', '电视模式'],
  'effect': '电视模式',
};

const Map<String, dynamic> _climateAttributes = <String, dynamic>{
  'friendly_name': '卧室空调',
  'temperature': 26.5,
  'min_temp': 16,
  'max_temp': 31,
  'target_temp_step': 0.5,
  'current_temperature': 35.0,
  'current_humidity': 55,
  'hvac_modes': <String>['cool', 'heat', 'off'],
  'fan_modes': <String>['自动', '三档'],
  'fan_mode': '三档',
  'swing_modes': <String>['off', 'vertical'],
  'swing_mode': 'off',
};

void main() {
  setUp(() {
    getIt.registerLazySingleton<LogService>(() => const LogService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('HomeBloc 加载', () {
    test('LoadHome 成功：实体入缓存，quickControls 灯在前、开关在后', () async {
      final _FakeHomeRepository repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('switch.plug', 'on'),
          _entity('light.bedroom', 'on'),
          _entity('sensor.temp', '24'),
        ],
      );
      final HomeBloc bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);

      expect(await _load(bloc), isTrue);
      expect(bloc.state.entities.length, 3);
      expect(
        bloc.state.quickControls.map((e) => e.entityId).toList(),
        <String>['light.bedroom', 'switch.plug'],
      );
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.errorMessage, isNull);

      // 全实体分组：sensor 也会成组，但没有可开关主实体
      expect(bloc.state.deviceGroups.length, 3);
      final HaDeviceGroup sensorGroup = bloc.state.deviceGroups
          .firstWhere((HaDeviceGroup g) => g.title == 'sensor.temp');
      expect(sensorGroup.primary, isNull);
      expect(sensorGroup.statusLabel, contains('可用'));
    });

    test('LoadHome 失败：写入 errorMessage 与 errorType', () async {
      final _FakeHomeRepository repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[],
      )..fetchError = const HaDisconnectException();
      final HomeBloc bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);

      expect(await _load(bloc), isFalse);
      expect(bloc.state.errorMessage, '与 Home Assistant 的连接已断开');
      expect(bloc.state.errorType, NetErrorType.disconnect);
    });
  });

  group('HomeBloc 开关控制', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('light.bedroom', 'on'),
          _entity('switch.plug', 'off'),
        ],
      );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('成功：乐观翻转 + 指令下发后清理 pending', () async {
      expect(
        await _toggle(bloc, 'light.bedroom'),
        isTrue,
      );
      expect(repo.toggleCalls, <(String, bool)>[('light.bedroom', false)]);
      expect(bloc.state.entities['light.bedroom']!.isOn, isFalse);
      expect(bloc.state.togglingIds, isEmpty);
      expect(bloc.state.errorMessage, isNull);
    });

    test('失败：回滚到原状态并写入错误', () async {
      repo.toggleError = const HaRequestException(1, '设备离线');

      expect(
        await _toggle(bloc, 'light.bedroom'),
        isFalse,
      );
      expect(bloc.state.entities['light.bedroom']!.isOn, isTrue,
          reason: '控制失败必须回滚乐观更新');
      expect(bloc.state.togglingIds, isEmpty);
      expect(bloc.state.errorMessage, '设备离线');
      expect(bloc.state.errorType, NetErrorType.requestError);
    });

    test('不可控实体（sensor 域）直接拒绝', () async {
      repo.states = <HaEntityStateModel>[_entity('sensor.temp', '24')];
      expect(await _load(bloc), isTrue);

      expect(
        await _toggle(bloc, 'sensor.temp'),
        isFalse,
      );
      expect(repo.toggleCalls, isEmpty);
    });

    test('实时事件：更新已加载实体，忽略未加载实体', () async {
      repo.emitChange(_entity('light.bedroom', 'off'));
      await bloc.stream.firstWhere(
        (HomeState s) => s.entities['light.bedroom']?.state == 'off',
      );
      expect(bloc.state.entities['light.bedroom']!.isOn, isFalse);

      final int before = bloc.state.entities.length;
      repo.emitChange(_entity('light.not_loaded', 'on'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.entities.length, before);
    });

    test('ClearHomeError 清除错误提示', () async {
      repo.toggleError = const HaRequestException(1, '失败');
      await _toggle(bloc, 'light.bedroom');
      expect(bloc.state.errorMessage, isNotNull);

      bloc.add(const ClearHomeError());
      await bloc.stream.firstWhere((HomeState s) => s.errorMessage == null);
      expect(bloc.state.errorMessage, isNull);
    });
  });

  group('HomeBloc 房间分组', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('light.bedroom', 'on'),
          _entity('light.living', 'off'),
          _entity('switch.plug', 'off'),
        ],
      )
        ..registry = HaRegistry(
          areas: <HaArea>[
            const HaArea(areaId: 'living', name: '客厅'),
            const HaArea(areaId: 'bedroom', name: '卧室'),
            const HaArea(areaId: 'kitchen', name: '厨房'),
          ],
          areaIdByEntity: <String, String>{
            'light.bedroom': 'bedroom',
            'light.living': 'living',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('availableAreas 仅含可控实体的房间，数量与归属标注正确', () {
      expect(
        bloc.state.availableAreas.map((HaArea a) => a.name).toList(),
        <String>['客厅', '卧室'],
        reason: '厨房无可控实体，不应出现',
      );
      expect(bloc.state.areaCount('living'), 1);
      expect(bloc.state.areaLabelFor('light.living'), '客厅');
      expect(bloc.state.areaLabelFor('switch.plug'), '未分配房间');
    });

    test('AreaSelected 按房间过滤网格，切回全部恢复', () async {
      bloc.add(const AreaSelected('bedroom'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedAreaId == 'bedroom');
      expect(
        bloc.state.quickControls.map((e) => e.entityId).toList(),
        <String>['light.bedroom'],
      );

      bloc.add(const AreaSelected(''));
      await bloc.stream.firstWhere((HomeState s) => s.selectedAreaId.isEmpty);
      expect(bloc.state.quickControls.length, 3);
    });

    test('所选房间不在可筛选集合时回退「全部」', () async {
      bloc.add(const AreaSelected('kitchen'));
      await bloc.stream.firstWhere(
        (HomeState s) =>
            s.selectedAreaId == 'kitchen' && s.effectiveAreaId.isEmpty,
      );
      expect(bloc.state.quickControls.length, 3);
    });

    test('重新加载后所选房间从注册表消失则自动清空', () async {
      bloc.add(const AreaSelected('bedroom'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedAreaId == 'bedroom');

      repo.registry = const HaRegistry(
        areas: <HaArea>[HaArea(areaId: 'living', name: '客厅')],
      );
      expect(await _load(bloc), isTrue);
      expect(bloc.state.selectedAreaId, '');
    });
  });

  group('HomeBloc 家庭分组', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('light.jk_living', 'on'),
          _entity('light.jk_bedroom', 'on'),
          _entity('light.td_living', 'off'),
          _entity('switch.legacy', 'off'),
        ],
      )
        ..registry = const HaRegistry(
          areas: <HaArea>[
            HaArea(areaId: 'legacy', name: '客厅'),
            HaArea(areaId: 'jk_kt', name: '金科1204 客厅'),
            HaArea(areaId: 'jk_ws', name: '金科1204 卧室'),
            HaArea(areaId: 'td_kt', name: '棠德304 客厅'),
          ],
          areaIdByEntity: <String, String>{
            'light.jk_living': 'jk_kt',
            'light.jk_bedroom': 'jk_ws',
            'light.td_living': 'td_kt',
            'switch.legacy': 'legacy',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('availableHomes 仅含命名家庭，数量统计正确', () {
      expect(
        bloc.state.availableHomes,
        <String>['金科1204', '棠德304'],
        reason: '未分配家庭的 legacy 客厅不进家庭标签',
      );
      expect(bloc.state.homeCount('金科1204'), 2);
      expect(bloc.state.homeCount('棠德304'), 1);
      expect(bloc.state.visibleAreas.length, 4, reason: '未选家庭时展示全部房间');
    });

    test('HomeSelected 按家庭过滤，未分配家庭的实体被排除', () async {
      bloc.add(const HomeSelected('金科1204'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedHomeName == '金科1204');
      expect(
        bloc.state.quickControls.map((e) => e.entityId).toList(),
        <String>['light.jk_bedroom', 'light.jk_living'],
      );
      expect(
        bloc.state.visibleAreas.map((a) => a.areaId).toList(),
        <String>['jk_kt', 'jk_ws'],
      );
      expect(
        bloc.state.areaLabelFor('light.jk_living'),
        '客厅',
        reason: '选中家庭时卡片房间用短名',
      );
    });

    test('切换家庭清空房间选择；未选家庭时卡片用完整区域名', () async {
      bloc.add(const HomeSelected('金科1204'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedHomeName == '金科1204');
      bloc.add(const AreaSelected('jk_kt'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedAreaId == 'jk_kt');

      bloc.add(const HomeSelected('棠德304'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedHomeName == '棠德304');
      expect(bloc.state.selectedAreaId, '', reason: '切换家庭必须清空房间选择');
      expect(bloc.state.quickControls.single.entityId, 'light.td_living');

      bloc.add(const HomeSelected(''));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedHomeName.isEmpty);
      expect(bloc.state.areaLabelFor('light.jk_living'), '金科1204 客厅');
      expect(bloc.state.quickControls.length, 4);
    });

    test('所选家庭失效时回退「全部」', () async {
      bloc.add(const HomeSelected('不存在的家'));
      await bloc.stream.firstWhere(
        (HomeState s) =>
            s.selectedHomeName == '不存在的家' &&
            s.effectiveHomeName.isEmpty,
      );
      expect(bloc.state.quickControls.length, 4);
    });

    test('重新加载后所选家庭从注册表消失则自动清空', () async {
      bloc.add(const HomeSelected('金科1204'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedHomeName == '金科1204');

      repo.registry = const HaRegistry(
        areas: <HaArea>[HaArea(areaId: 'td_kt', name: '棠德304 客厅')],
      );
      expect(await _load(bloc), isTrue);
      expect(bloc.state.selectedHomeName, '');
      expect(bloc.state.selectedAreaId, '');
    });
  });

  group('HomeBloc 设备分组', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('light.fan_light', 'on'),
          _entity('switch.fan_delay', 'off'),
          _entity('light.plant_light', 'on'),
          _entity('switch.plant_power', 'off'),
          _entity('switch.lonely', 'off'),
        ],
      )
        ..registry = const HaRegistry(
          areas: <HaArea>[
            HaArea(areaId: 'balcony', name: '金科1204 阳台'),
            HaArea(areaId: 'bedroom', name: '金科1204 卧室'),
          ],
          devices: <String, HaDevice>{
            'dev_fan': HaDevice(id: 'dev_fan', name: '风扇灯'),
            'dev_plant': HaDevice(id: 'dev_plant', name: '阳台植物灯'),
          },
          deviceIdByEntity: <String, String>{
            'light.fan_light': 'dev_fan',
            'switch.fan_delay': 'dev_fan',
            'light.plant_light': 'dev_plant',
            'switch.plant_power': 'dev_plant',
          },
          areaIdByEntity: <String, String>{
            'light.fan_light': 'balcony',
            'switch.fan_delay': 'balcony',
            'light.plant_light': 'bedroom',
            'switch.plant_power': 'bedroom',
            'switch.lonely': 'bedroom',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('同设备实体合并为一张卡，标题用设备名', () {
      final List<HaDeviceGroup> groups = bloc.state.deviceGroups;
      expect(groups.length, 3, reason: '5 个可控实体 → 3 张设备卡');

      final HaDeviceGroup fan =
          groups.singleWhere((HaDeviceGroup g) => g.deviceId == 'dev_fan');
      expect(fan.title, '风扇灯');
      expect(fan.isMerged, isTrue);
      expect(fan.primary!.entityId, 'light.fan_light',
          reason: '真灯应被选为主实体');
      expect(fan.onCount, 1);
      expect(fan.statusLabel, '已开启 1/2');
    });

    test('卡片角标按设备卡计数，同设备多实体只算一次', () {
      expect(bloc.state.areaCount('balcony'), 1, reason: '风扇灯 2 实体合并为 1 卡');
      expect(bloc.state.areaCount('bedroom'), 2, reason: '植物灯 + 孤独开关 = 2 卡');
      expect(bloc.state.homeCount('金科1204'), 3);
      expect(bloc.state.quickControls.length, 5, reason: '实体级列表不受合并影响');
    });

    test('deviceGroupOf 按设备查分组，不受家庭/房间筛选影响', () async {
      bloc.add(const AreaSelected('balcony'));
      await bloc.stream
          .firstWhere((HomeState s) => s.selectedAreaId == 'balcony');
      expect(bloc.state.deviceGroups.length, 1, reason: '筛选只留阳台卡');

      final HaDeviceGroup? plant = bloc.state.deviceGroupOf('dev_plant');
      expect(plant, isNotNull, reason: '详情页入口不依赖当前筛选');
      expect(plant!.title, '阳台植物灯');
      expect(
        plant.entities.map((HaEntityStateModel e) => e.entityId).toList(),
        <String>['light.plant_light', 'switch.plant_power'],
      );
      expect(bloc.state.deviceGroupOf('dev_unknown'), isNull);
    });

    test('注册表降级（无设备映射）时退化为一实体一卡', () async {
      repo.registry = const HaRegistry(
        areas: <HaArea>[HaArea(areaId: 'bedroom', name: '金科1204 卧室')],
        areaIdByEntity: <String, String>{
          'light.fan_light': 'bedroom',
          'switch.fan_delay': 'bedroom',
          'light.plant_light': 'bedroom',
          'switch.plant_power': 'bedroom',
          'switch.lonely': 'bedroom',
        },
      );
      expect(await _load(bloc), isTrue);
      expect(bloc.state.deviceGroups.length, 5, reason: '无映射时逐实体成卡');
      expect(
        bloc.state.deviceGroups.every((HaDeviceGroup g) => g.deviceId == null),
        isTrue,
      );
      expect(bloc.state.areaCount('bedroom'), 5);
    });
  });

  group('HomeBloc 参数控制', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('light.bedroom', 'on', attributes: _lightAttributes),
          _entity('climate.bedroom', 'cool', attributes: _climateAttributes),
        ],
      );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('亮度：乐观写入 0-255 属性，下发百分比', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetLightBrightness(
            entityId: 'light.bedroom',
            percent: 50,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.brightnessCalls, <(String, int)>[('light.bedroom', 50)]);
      expect(bloc.state.entities['light.bedroom']!.brightnessValue, 128);
      expect(bloc.state.errorMessage, isNull);
    });

    test('色温：超出范围时夹到 min/max', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetLightColorTemperature(
            entityId: 'light.bedroom',
            kelvin: 1000,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.colorTempCalls, <(String, int)>[('light.bedroom', 2700)]);
      expect(bloc.state.entities['light.bedroom']!.colorTempKelvin, 2700);
    });

    test('灯光效果：仅接受 effect_list 中的值', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetLightEffect(
            entityId: 'light.bedroom',
            effect: '电视模式',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.effectCalls, <(String, String)>[('light.bedroom', '电视模式')]);

      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetLightEffect(
            entityId: 'light.bedroom',
            effect: '不存在',
            completer: c,
          )),
        ),
        isFalse,
      );
      expect(repo.effectCalls.length, 1, reason: '非法效果不应下发');
    });

    test('空调温度：按 0.5 步进并夹在 16-31', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetClimateTemperature(
            entityId: 'climate.bedroom',
            temperature: 40,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.climateTempCalls,
          <(String, double)>[('climate.bedroom', 31.0)]);
      expect(bloc.state.entities['climate.bedroom']!.targetTemperature, 31.0);

      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetClimateTemperature(
            entityId: 'climate.bedroom',
            temperature: 26.7,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(bloc.state.entities['climate.bedroom']!.targetTemperature, 26.5,
          reason: '0.5 步进应把 26.7 归到 26.5');
    });

    test('空调模式 / 风速 / 摆风', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetClimateHvacMode(
            entityId: 'climate.bedroom',
            mode: 'heat',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(bloc.state.entities['climate.bedroom']!.state, 'heat');

      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetClimateFanMode(
            entityId: 'climate.bedroom',
            mode: '自动',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(bloc.state.entities['climate.bedroom']!.fanMode, '自动');

      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetClimateSwingMode(
            entityId: 'climate.bedroom',
            mode: 'vertical',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(bloc.state.entities['climate.bedroom']!.swingMode, 'vertical');

      expect(repo.hvacModeCalls,
          <(String, String)>[('climate.bedroom', 'heat')]);
      expect(repo.fanModeCalls, <(String, String)>[('climate.bedroom', '自动')]);
      expect(repo.swingModeCalls,
          <(String, String)>[('climate.bedroom', 'vertical')]);
    });

    test('空调开关：cool 状态切换为 turn_off，isOn 随模式变化', () async {
      expect(await _toggle(bloc, 'climate.bedroom'), isTrue);
      expect(repo.toggleCalls,
          <(String, bool)>[('climate.bedroom', false)]);
      expect(bloc.state.entities['climate.bedroom']!.isOn, isFalse);
    });

    test('参数控制失败：回滚原属性并写入错误', () async {
      repo.controlError = const HaRequestException(1, '设备离线');

      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetLightBrightness(
            entityId: 'light.bedroom',
            percent: 30,
            completer: c,
          )),
        ),
        isFalse,
      );
      expect(bloc.state.entities['light.bedroom']!.brightnessValue, 204,
          reason: '失败必须回滚亮度');
      expect(bloc.state.errorMessage, '设备离线');
    });
  });

  group('HomeBloc 洗衣机控制', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('switch.wm_on_p_2_1', 'off', attributes: const <String, dynamic>{
            'friendly_name': '米家洗衣机 洗衣机 开关',
          }),
          _entity('switch.wm_alarm', 'on', attributes: const <String, dynamic>{
            'friendly_name': '米家洗衣机 提示音 提示音',
          }),
          _entity('select.wm_mode_p_2_3', '智能洗',
              attributes: const <String, dynamic>{
                'friendly_name': '米家洗衣机 洗衣机 模式',
                'options': <String>['智能洗', '快速洗', '单烘干'],
              }),
          _entity('button.wm_start_wash_a_2_2', 'unknown',
              attributes: const <String, dynamic>{
                'friendly_name': '米家洗衣机 洗衣机 开始洗涤',
              }),
          _entity('sensor.wm_status_p_2_2', '已关机',
              attributes: const <String, dynamic>{
                'friendly_name': '米家洗衣机 洗衣机 工作状态',
              }),
          _entity('sensor.wm_run_status_p_2_11', '未运行',
              attributes: const <String, dynamic>{
                'friendly_name': '米家洗衣机 洗衣机 运行状态',
              }),
        ],
      )
        ..registry = const HaRegistry(
          devices: <String, HaDevice>{
            'dev_wm': HaDevice(id: 'dev_wm', name: '米家洗衣机 洗烘12kg'),
          },
          deviceIdByEntity: <String, String>{
            'switch.wm_on_p_2_1': 'dev_wm',
            'switch.wm_alarm': 'dev_wm',
            'select.wm_mode_p_2_3': 'dev_wm',
            'button.wm_start_wash_a_2_2': 'dev_wm',
            'sensor.wm_status_p_2_2': 'dev_wm',
            'sensor.wm_run_status_p_2_11': 'dev_wm',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('washerSummaries 选出真正的电源开关', () {
      final WasherSummary? summary = bloc.state.washerSummaries['dev_wm'];
      expect(summary, isNotNull);
      expect(summary!.powerEntityId, 'switch.wm_on_p_2_1',
          reason: '不能选到提示音 / 静音');
      expect(summary.isOn, isFalse);
      expect(summary.modes, <String>['智能洗', '快速洗', '单烘干']);
    });

    test('选择模式：乐观更新并下发 select_option', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SelectEntityOption(
            entityId: 'select.wm_mode_p_2_3',
            option: '快速洗',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.selectCalls,
          <(String, String)>[('select.wm_mode_p_2_3', '快速洗')]);
      expect(bloc.state.entities['select.wm_mode_p_2_3']!.state, '快速洗');
    });

    test('按钮：unknown 状态也可以按下', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(PressEntityButton(
            entityId: 'button.wm_start_wash_a_2_2',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.buttonCalls, <String>['button.wm_start_wash_a_2_2']);
    });

    test('按钮失败：写入错误提示', () async {
      repo.controlError = const HaRequestException(1, '设备离线');
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(PressEntityButton(
            entityId: 'button.wm_start_wash_a_2_2',
            completer: c,
          )),
        ),
        isFalse,
      );
      expect(bloc.state.errorMessage, '设备离线');
    });
  });

  group('HomeBloc 热水器控制', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('water_heater.wh', '自定义',
              attributes: const <String, dynamic>{
                'friendly_name': '米家智能零冷水燃气热水器16L N1  热水器',
                'min_temp': 35,
                'max_temp': 65,
                'target_temp_step': 1,
                'temperature': 40,
                'current_temperature': 33,
                'operation_list': <String>[
                  '自定义',
                  'AI控温',
                  '婴童洗',
                  '舒适洗',
                  '宠物洗',
                  '厨房用',
                  'off',
                ],
              }),
          _entity('switch.wh_hot_water_recirculation_p_2_10', 'off',
              attributes: const <String, dynamic>{
                'friendly_name': '米家智能零冷水燃气热水器16L N1  热水器 预热',
              }),
          _entity('sensor.wh_status_p_2_5', '待机中',
              attributes: const <String, dynamic>{
                'friendly_name': '米家智能零冷水燃气热水器16L N1  热水器 工作状态',
              }),
          _entity(
            'text.wh_preheat_timer_p_2_13',
            '0&2315&2316&0&0-0&0000&0000&0&9-0&0000&0000&0&9'
            '-0&0000&0000&0&9-0&0000&0000&0&9',
            attributes: const <String, dynamic>{
              'friendly_name':
                  '米家智能零冷水燃气热水器16L N1  热水器 预热定时（格式规范）',
            },
          ),
        ],
      )
        ..registry = const HaRegistry(
          devices: <String, HaDevice>{
            'dev_wh': HaDevice(
              id: 'dev_wh',
              name: '米家智能零冷水燃气热水器16L N1',
            ),
          },
          deviceIdByEntity: <String, String>{
            'water_heater.wh': 'dev_wh',
            'switch.wh_hot_water_recirculation_p_2_10': 'dev_wh',
            'sensor.wh_status_p_2_5': 'dev_wh',
            'text.wh_preheat_timer_p_2_13': 'dev_wh',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('waterHeaterSummaries 解析目标温度与模式', () {
      final WaterHeaterSummary? summary =
          bloc.state.waterHeaterSummaries['dev_wh'];
      expect(summary, isNotNull);
      expect(summary!.isOn, isTrue);
      expect(summary.targetTemperature, 40);
      expect(summary.modes.length, 6);
      expect(summary.preheatEntityId, 'switch.wh_hot_water_recirculation_p_2_10');
    });

    test('设置目标温度：夹在 35-65', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetWaterHeaterTemperature(
            entityId: 'water_heater.wh',
            temperature: 70,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.waterHeaterTempCalls,
          <(String, double)>[('water_heater.wh', 65.0)]);
      expect(bloc.state.entities['water_heater.wh']!.targetTemperature, 65);
    });

    test('切换洗浴模式', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetWaterHeaterOperationMode(
            entityId: 'water_heater.wh',
            mode: 'AI控温',
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.waterHeaterModeCalls,
          <(String, String)>[('water_heater.wh', 'AI控温')]);
      expect(bloc.state.entities['water_heater.wh']!.state, 'AI控温');
    });

    test('热水器开关：自定义状态切换为 turn_off', () async {
      expect(await _toggle(bloc, 'water_heater.wh'), isTrue);
      expect(repo.toggleCalls,
          <(String, bool)>[('water_heater.wh', false)]);
      expect(bloc.state.entities['water_heater.wh']!.isOn, isFalse);
    });

    test('写入定时预热编码串', () async {
      const String value =
          '0&2315&2316&1&0-0&0000&0000&0&9-0&0000&0000&0&9'
          '-0&0000&0000&0&9-0&0000&0000&0&9';
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetTextEntityValue(
            entityId: 'text.wh_preheat_timer_p_2_13',
            value: value,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.textCalls, <(String, String)>[('text.wh_preheat_timer_p_2_13', value)]);
      expect(bloc.state.entities['text.wh_preheat_timer_p_2_13']!.state, value);
    });
  });

  group('HomeBloc 热水瓶控制', () {
    late _FakeHomeRepository repo;
    late HomeBloc bloc;

    setUp(() async {
      repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity('sensor.k_status_p_2_1', '待机中',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 工作状态',
              }),
          _entity('sensor.k_temperature_p_2_6', '51',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 温度',
              }),
          _entity('select.k_mode_p_2_3', '自来水',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 模式',
                'options': <String>['自来水', '纯净水', '凉白开'],
              }),
          _entity('number.k_target_temperature_p_2_5', '100',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 设定温度',
              }),
          _entity('switch.k_auto_keep_warm_p_2_7', 'on',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 保温',
              }),
          _entity('notify.k_start_cook_a_2_1', 'unknown',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 开始加热',
              }),
          _entity('button.k_cancel_cooking_a_2_2', 'unknown',
              attributes: const <String, dynamic>{
                'friendly_name': '热水瓶 停止',
              }),
        ],
      )
        ..registry = const HaRegistry(
          devices: <String, HaDevice>{
            'dev_k': HaDevice(id: 'dev_k', name: '米家智能电热水瓶 5L'),
          },
          deviceIdByEntity: <String, String>{
            'sensor.k_status_p_2_1': 'dev_k',
            'sensor.k_temperature_p_2_6': 'dev_k',
            'select.k_mode_p_2_3': 'dev_k',
            'number.k_target_temperature_p_2_5': 'dev_k',
            'switch.k_auto_keep_warm_p_2_7': 'dev_k',
            'notify.k_start_cook_a_2_1': 'dev_k',
            'button.k_cancel_cooking_a_2_2': 'dev_k',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('kettleSummaries 解析内置模式与参数', () {
      final KettleSummary? summary = bloc.state.kettleSummaries['dev_k'];
      expect(summary, isNotNull);
      expect(summary!.mode, '自来水');
      expect(summary.targetTemperature, 100);
      expect(summary.keepWarmOn, isTrue);
      expect(summary.startEntityId, 'notify.k_start_cook_a_2_1');
    });

    test('设置 number 目标温度', () async {
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(SetNumberEntityValue(
            entityId: 'number.k_target_temperature_p_2_5',
            value: 95,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.numberCalls,
          <(String, double)>[('number.k_target_temperature_p_2_5', 95)]);
      expect(bloc.state.entities['number.k_target_temperature_p_2_5']!.state, '95');
    });

    test('notify 开始加热', () async {
      final String message =
          bloc.state.kettleSummaries['dev_k']!.startMessage;
      expect(
        await _run(
          bloc,
          (Completer<bool> c) => bloc.add(PressNotifyAction(
            entityId: 'notify.k_start_cook_a_2_1',
            message: message,
            completer: c,
          )),
        ),
        isTrue,
      );
      expect(repo.notifyCalls,
          <(String, String)>[('notify.k_start_cook_a_2_1', message)]);
    });
  });

  group('HomeState 家庭温湿度概览', () {    late HomeBloc bloc;

    setUp(() async {
      final _FakeHomeRepository repo = _FakeHomeRepository(
        states: <HaEntityStateModel>[
          _entity(
            'climate.jk_ac',
            'cool',
            attributes: const <String, dynamic>{
              'friendly_name': '金科空调',
              'current_temperature': 34.9,
              'current_humidity': 56,
            },
          ),
          // 同家庭里先出现一台只有温度的设备：应被「温+湿」的更完整来源取代
          _entity(
            'climate.td_plug',
            'off',
            attributes: const <String, dynamic>{
              'friendly_name': '空调插座',
              'current_temperature': 30.0,
            },
          ),
          _entity(
            'climate.td_ac',
            'off',
            attributes: const <String, dynamic>{
              'friendly_name': '棠德空调',
              'current_temperature': 29.4,
              'current_humidity': 71,
            },
          ),
          // 离线设备即使带旧值也不参与
          _entity(
            'climate.td_offline',
            'unavailable',
            attributes: const <String, dynamic>{
              'friendly_name': '离线空调',
              'current_temperature': 20.0,
              'current_humidity': 40,
            },
          ),
          // 该家庭没有空调，只有开关 → 概览条目存在但温湿度为空
          _entity('switch.sz_plug', 'off'),
        ],
      )
        ..registry = const HaRegistry(
          areas: <HaArea>[
            HaArea(areaId: 'jk_ws', name: '金科1204 卧室'),
            HaArea(areaId: 'td_ws', name: '棠德304 卧室'),
            HaArea(areaId: 'sz_3f', name: '薯仔4号的家 3楼房间'),
          ],
          areaIdByEntity: <String, String>{
            'climate.jk_ac': 'jk_ws',
            'climate.td_plug': 'td_ws',
            'climate.td_ac': 'td_ws',
            'climate.td_offline': 'td_ws',
            'switch.sz_plug': 'sz_3f',
          },
        );
      bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      expect(await _load(bloc), isTrue);
    });

    test('按家庭聚合：优先温+湿来源，缺失项为 null', () {
      final List<HomeClimateSummary> summaries =
          bloc.state.homeClimateSummaries;
      expect(
        summaries.map((HomeClimateSummary s) => s.homeName).toList(),
        <String>['金科1204', '棠德304', '薯仔4号的家'],
      );

      final HomeClimateSummary jk = summaries[0];
      expect(jk.temperature, 34.9);
      expect(jk.humidity, 56);
      expect(jk.sourceName, '金科空调');
      expect(jk.hasData, isTrue);

      final HomeClimateSummary td = summaries[1];
      expect(td.temperature, 29.4,
          reason: '应选同时有温度和湿度的空调');
      expect(td.humidity, 71);
      expect(td.sourceName, '棠德空调');

      final HomeClimateSummary sz = summaries[2];
      expect(sz.hasData, isFalse);
      expect(sz.temperature, isNull);
      expect(sz.humidity, isNull);
    });
  });
}

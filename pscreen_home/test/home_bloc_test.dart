import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 内存版 HomeRepository：可控成功/失败，可注入实时状态事件
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({required this.states});

  List<HaEntityStateModel> states;
  HaRegistry registry = HaRegistry.empty;
  Object? fetchError;
  Object? toggleError;
  final List<(String, bool)> toggleCalls = <(String, bool)>[];
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

  void emitChange(HaEntityStateModel entity) => _events.add(entity);
}

HaEntityStateModel _entity(String entityId, String state) => HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{'friendly_name': entityId},
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
}

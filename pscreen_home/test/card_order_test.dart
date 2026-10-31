import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/card_order_planner.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';

HaEntityStateModel _entity(String entityId) => HaEntityStateModel(
  entityId: entityId,
  state: 'on',
  attributes: <String, dynamic>{'friendly_name': entityId},
);

void main() {
  group('CardOrderPlanner', () {
    const List<String> current = <String>['a1', 'b1', 'a2', 'b2'];
    const Map<String, String> homeByKey = <String, String>{
      'a1': 'A',
      'a2': 'A',
      'b1': 'B',
      'b2': 'B',
    };

    test('家庭拖动：同步全局槽位，其他家庭不动', () {
      final CardOrderPlan plan = CardOrderPlanner.apply(
        allOrder: current,
        homeOrders: const <String, List<String>>{
          'A': <String>['a1', 'a2'],
          'B': <String>['b1', 'b2'],
        },
        allCurrentKeys: current,
        homeByKey: homeByKey,
        viewHome: 'A',
        visibleNewOrder: const <String>['a2', 'a1'],
      );

      expect(plan.homeOrders['A'], <String>['a2', 'a1']);
      expect(plan.homeOrders['B'], <String>['b1', 'b2']);
      expect(plan.allOrder, <String>['a2', 'b1', 'a1', 'b2']);
    });

    test('房间拖动：只替换该房间在家庭中的槽位', () {
      const List<String> keys = <String>['a1', 'b1', 'a2', 'a3', 'b2'];
      final CardOrderPlan plan = CardOrderPlanner.apply(
        allOrder: keys,
        homeOrders: const <String, List<String>>{
          'A': <String>['a1', 'a2', 'a3'],
          'B': <String>['b1', 'b2'],
        },
        allCurrentKeys: keys,
        homeByKey: const <String, String>{
          'a1': 'A',
          'a2': 'A',
          'a3': 'A',
          'b1': 'B',
          'b2': 'B',
        },
        viewHome: 'A',
        // 客厅只有 a1、a2；a3 是卧室，保持原槽位。
        visibleNewOrder: const <String>['a2', 'a1'],
      );

      expect(plan.homeOrders['A'], <String>['a2', 'a1', 'a3']);
      expect(plan.allOrder, <String>['a2', 'b1', 'a1', 'a3', 'b2']);
    });

    test('全部拖动：只改全局，不反写家庭顺序', () {
      final CardOrderPlan plan = CardOrderPlanner.apply(
        allOrder: const <String>['a1', 'b1', 'a2'],
        homeOrders: const <String, List<String>>{
          'A': <String>['a1', 'a2'],
          'B': <String>['b1'],
        },
        allCurrentKeys: const <String>['a1', 'b1', 'a2'],
        homeByKey: homeByKey,
        viewHome: '',
        visibleNewOrder: const <String>['a2', 'b1', 'a1'],
      );

      expect(plan.allOrder, <String>['a2', 'b1', 'a1']);
      expect(plan.homeOrders['A'], <String>['a1', 'a2']);
      expect(plan.homeOrders['B'], <String>['b1']);
    });

    test('merge：保留墓碑，新卡片追加末尾，去重', () {
      expect(
        CardOrderPlanner.merge(
          const <String>['a1', 'gone', 'a1'],
          const <String>['a1', 'a2'],
        ),
        <String>['a1', 'gone', 'a2'],
      );
      expect(
        CardOrderPlanner.merge(const <String>[], const <String>['b1', 'a1']),
        <String>['b1', 'a1'],
      );
    });

    test('新卡片在家庭视图追加到家庭末尾并同步全局', () {
      final CardOrderPlan plan = CardOrderPlanner.apply(
        allOrder: const <String>['a1', 'b1'],
        homeOrders: const <String, List<String>>{
          'A': <String>['a1'],
          'B': <String>['b1'],
        },
        allCurrentKeys: const <String>['a1', 'b1', 'a2'],
        homeByKey: homeByKey,
        viewHome: 'A',
        visibleNewOrder: const <String>['a2', 'a1'],
      );

      expect(plan.homeOrders['A'], <String>['a2', 'a1']);
      expect(plan.allOrder, <String>['a2', 'b1', 'a1']);
    });
  });

  group('HomeState 卡片顺序', () {
    const HaRegistry registry = HaRegistry(
      areas: <HaArea>[
        HaArea(areaId: 'a_living', name: 'A 客厅'),
        HaArea(areaId: 'a_bed', name: 'A 卧室'),
        HaArea(areaId: 'b_living', name: 'B 客厅'),
      ],
      devices: <String, HaDevice>{
        'dev_a1': HaDevice(id: 'dev_a1', name: 'A1'),
        'dev_a2': HaDevice(id: 'dev_a2', name: 'A2'),
        'dev_b1': HaDevice(id: 'dev_b1', name: 'B1'),
      },
      areaIdByEntity: <String, String>{
        'light.a1': 'a_living',
        'light.a2': 'a_bed',
        'light.b1': 'b_living',
      },
      deviceIdByEntity: <String, String>{
        'light.a1': 'dev_a1',
        'light.a2': 'dev_a2',
        'light.b1': 'dev_b1',
      },
    );

    HomeState state({
      List<String> all = const <String>[],
      Map<String, List<String>> byHome = const <String, List<String>>{},
      String home = '',
      String area = '',
    }) {
      return HomeState.initial().copyWith(
        entities: <String, HaEntityStateModel>{
          'light.a1': _entity('light.a1'),
          'light.a2': _entity('light.a2'),
          'light.b1': _entity('light.b1'),
        },
        registry: registry,
        selectedHomeName: home,
        selectedAreaId: area,
        cardOrderAll: all,
        cardOrderByHome: byHome,
      );
    }

    test('全部视图按全局顺序，未保存的新卡片追加末尾', () {
      final HomeState s = state(all: const <String>['device:dev_b1']);
      expect(s.deviceGroups.map((g) => g.orderKey).toList(), <String>[
        'device:dev_b1',
        'device:dev_a1',
        'device:dev_a2',
      ]);
    });

    test('家庭视图优先家庭顺序，缺失时回落全局子序列', () {
      final HomeState withHome = state(
        all: const <String>['device:dev_b1', 'device:dev_a2', 'device:dev_a1'],
        byHome: const <String, List<String>>{
          'A': <String>['device:dev_a2', 'device:dev_a1'],
        },
        home: 'A',
      );
      expect(withHome.deviceGroups.map((g) => g.orderKey).toList(), <String>[
        'device:dev_a2',
        'device:dev_a1',
      ]);

      final HomeState fallback = state(
        all: const <String>['device:dev_b1', 'device:dev_a2', 'device:dev_a1'],
        home: 'A',
      );
      expect(fallback.deviceGroups.map((g) => g.orderKey).toList(), <String>[
        'device:dev_a2',
        'device:dev_a1',
      ]);
    });

    test('房间视图按家庭顺序过滤', () {
      final HomeState s = state(
        all: const <String>['device:dev_a2', 'device:dev_a1'],
        byHome: const <String, List<String>>{
          'A': <String>['device:dev_a2', 'device:dev_a1'],
        },
        home: 'A',
        area: 'a_bed',
      );
      expect(s.deviceGroups.map((g) => g.orderKey).toList(), <String>[
        'device:dev_a2',
      ]);
    });
  });
}

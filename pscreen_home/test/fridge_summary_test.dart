import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

HaEntityStateModel _e(
  String entityId,
  String state, {
  String? name,
  Map<String, dynamic> attributes = const <String, dynamic>{},
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{
        'friendly_name': ?name,
        ...attributes,
      },
    );

List<HaEntityStateModel> _entities({String fault = '0', String door = '0'}) =>
    <HaEntityStateModel>[
      _e(
        'select.midjd_mode_p_2_2',
        '智能',
        name: '随便改的名字 模式',
        attributes: const <String, dynamic>{
          'options': <String>['手动', '智能', '速冷', '速冻'],
        },
      ),
      _e('sensor.midjd_temperature_p_3_1', '7', name: '冷藏温度'),
      _e('sensor.midjd_temperature_p_4_1', '-20', name: '冷冻温度'),
      _e('sensor.midjd_temperature_p_6_1', '2', name: '变温温度'),
      _e('number.midjd_target_temperature_p_3_2', '5',
          name: '冷藏目标',
          attributes: const <String, dynamic>{'min': 2, 'max': 8}),
      _e('number.midjd_target_temperature_p_4_2', '-18',
          name: '冷冻目标',
          attributes: const <String, dynamic>{'min': -24, 'max': -16}),
      _e('number.midjd_target_temperature_p_6_2', '5',
          name: '变温目标',
          attributes: const <String, dynamic>{'min': -1, 'max': 5}),
      _e('sensor.midjd_fault_p_2_1', fault, name: '故障'),
      _e('sensor.midjd_door_not_close_remind_p_2_3', door, name: '门提醒'),
      _e('sensor.midjd_environment_temp_p_10_9', '29', name: '环境温度'),
      _e('sensor.midjd_environment_humidity_p_10_10', '70', name: '环境湿度'),
      _e('sensor.midjd_ref_open_times_p_10_38', '75', name: '冷藏开门'),
      _e('sensor.midjd_frz_open_times_p_10_40', '3', name: '冷冻开门'),
      _e('sensor.midjd_total_runtime_p_10_23', '1105', name: '运行时间'),
    ];

void main() {
  group('FridgeSummary', () {
    test('解析三舱温度 / 模式 / 环境信息', () {
      final FridgeSummary? summary = FridgeSummary.tryBuild(
        deviceId: 'dev_fridge',
        name: '米家冰箱 法式平嵌400L',
        entities: _entities(),
      );

      expect(summary, isNotNull);
      expect(summary!.mode, '智能');
      expect(summary.modes, <String>['手动', '智能', '速冷', '速冻']);
      expect(summary.zones.length, 3);
      expect(summary.zones[0].name, '冷藏室');
      expect(summary.zones[0].currentTemperature, 7);
      expect(summary.zones[0].targetTemperature, 5);
      expect(summary.zones[0].minTemperature, 2);
      expect(summary.zones[0].maxTemperature, 8);
      expect(summary.zones[1].targetTemperature, -18);
      expect(summary.zones[2].targetTemperature, 5);
      expect(summary.hasFault, isFalse);
      expect(summary.doorWarning, isFalse);
      expect(summary.environmentTemperature, 29);
      expect(summary.environmentHumidity, 70);
      expect(summary.statusLabel, '智能模式');
    });

    test('故障和门提醒会置为警告', () {
      final FridgeSummary fault = FridgeSummary.tryBuild(
        deviceId: 'd',
        name: 'f',
        entities: _entities(fault: '3'),
      )!;
      expect(fault.hasFault, isTrue);
      expect(fault.statusLabel, '故障');

      final FridgeSummary door = FridgeSummary.tryBuild(
        deviceId: 'd',
        name: 'f',
        entities: _entities(door: '1'),
      )!;
      expect(door.doorWarning, isTrue);
      expect(door.statusLabel, '有门未关');
    });

    test('不是冰箱时返回 null', () {
      final FridgeSummary? summary = FridgeSummary.tryBuild(
        deviceId: 'd',
        name: '普通开关',
        entities: <HaEntityStateModel>[
          _e('switch.other', 'off', name: '开关'),
        ],
      );
      expect(summary, isNull);
    });
  });
}

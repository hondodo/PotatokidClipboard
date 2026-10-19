import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';

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

List<HaEntityStateModel> _entities({String fault = '0'}) =>
    <HaEntityStateModel>[
      _e(
        'water_heater.wh',
        '自定义',
        name: '热水器',
        attributes: const <String, dynamic>{
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
        },
      ),
      _e('sensor.wh_status_p_2_5', '待机中', name: '热水器 工作状态'),
      _e('sensor.wh_fault_p_2_1', fault, name: '热水器 故障'),
      _e('sensor.wh_input_water_temperature_p_2_8', '31', name: '热水器 进水温度'),
      _e('sensor.wh_water_flow_p_2_9', '0.0', name: '热水器 水流量（L/MIN)'),
      _e(
        'switch.wh_hot_water_recirculation_p_2_10',
        'off',
        name: '热水器 热水器 预热',
      ),
      _e(
        'switch.wh_intelligent_preheat_p_2_17',
        'on',
        name: '热水器 热水器 智能定时预热',
      ),
    ];

void main() {
  group('WaterHeaterSummary', () {
    test('解析主实体 / 模式 / 预热 / 状态', () {
      final WaterHeaterSummary? summary = WaterHeaterSummary.tryBuild(
        deviceId: 'dev_wh',
        name: '米家智能零冷水燃气热水器16L N1',
        entities: _entities(),
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isTrue, reason: '自定义模式属于开启');
      expect(summary.targetTemperature, 40);
      expect(summary.currentTemperature, 33);
      expect(summary.minTemperature, 35);
      expect(summary.maxTemperature, 65);
      expect(summary.modes,
          <String>['自定义', 'AI控温', '婴童洗', '舒适洗', '宠物洗', '厨房用']);
      expect(summary.mode, '自定义');
      expect(summary.status, '待机中');
      expect(summary.inletTemperature, 31);
      expect(summary.flowRate, 0);
      expect(summary.preheatEntityId, 'switch.wh_hot_water_recirculation_p_2_10');
      expect(summary.preheatOn, isFalse);
      expect(summary.timerPreheatEntityId, 'switch.wh_intelligent_preheat_p_2_17');
      expect(summary.timerPreheatOn, isTrue);
      expect(summary.hasFault, isFalse);
    });

    test('故障码非 0 时标记故障', () {
      final WaterHeaterSummary summary = WaterHeaterSummary.tryBuild(
        deviceId: 'dev_wh',
        name: '热水器',
        entities: _entities(fault: 'E1'),
      )!;
      expect(summary.hasFault, isTrue);
    });

    test('没有 water_heater 主实体时返回 null', () {
      final WaterHeaterSummary? summary = WaterHeaterSummary.tryBuild(
        deviceId: 'dev_other',
        name: '普通开关',
        entities: <HaEntityStateModel>[
          _e('switch.other', 'off', name: '普通开关'),
        ],
      );
      expect(summary, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';

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

void main() {
  group('RangeHoodSummary', () {
    test('解析电源 / 风量 / 灯光 / 延时 / 巡航 / 假日', () {
      final RangeHoodSummary? summary = RangeHoodSummary.tryBuild(
        deviceId: 'dev_hood',
        name: '米家智能侧吸油烟机S1',
        entities: <HaEntityStateModel>[
          _e('switch.viomi_on_p_2_1', 'off', name: '电源'),
          _e('select.viomi_fan_level_p_10_2', '低风',
              name: '风量',
              attributes: const <String, dynamic>{
                'options': <String>['低风', '高风', '爆炒'],
              }),
          _e('light.viomi_s_5_light', 'off', name: '灯光'),
          _e('switch.viomi_off_delay_p_2_5', 'on', name: '延时关机'),
          _e('number.viomi_off_delay_time_p_2_4', '1', name: '延时时长'),
          _e('switch.viomi_cruise_on_p_9_5', 'off', name: '巡航'),
          _e('switch.viomi_holiday_on_p_9_6', 'off', name: '假日'),
          _e('sensor.viomi_fault_p_2_2', '0', name: '故障'),
          _e('sensor.viomi_dry_cleaning_status_p_11_2', '未启动', name: '干洗'),
          _e('sensor.viomi_left_status_p_6_5', 'On', name: '左灶'),
          _e('sensor.viomi_right_status_p_6_6', 'Off', name: '右灶'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isFalse);
      expect(summary.fanLevels, <String>['低风', '高风', '爆炒']);
      expect(summary.fanLevel, '低风');
      expect(summary.lightOn, isFalse);
      expect(summary.delayOn, isTrue);
      expect(summary.delayMinutes, 1);
      expect(summary.cruiseOn, isFalse);
      expect(summary.holidayOn, isFalse);
      expect(summary.isDryCleaning, isFalse);
      expect(summary.leftBurnerOn, isTrue);
      expect(summary.rightBurnerOn, isFalse);
      expect(summary.anyBurnerOn, isTrue);
      expect(summary.burnerStatusLabel, '左灶开启');
      expect(summary.statusLabel, '已关闭');
    });

    test('灶具 Low / Big 枚举视为开启', () {
      RangeHoodSummary build(String left, String right) =>
          RangeHoodSummary.tryBuild(
            deviceId: 'd',
            name: 'hood',
            entities: <HaEntityStateModel>[
              _e('switch.viomi_on_p_2_1', 'off', name: '电源'),
              _e('select.viomi_fan_level_p_10_2', '低风',
                  name: '风量',
                  attributes: const <String, dynamic>{
                    'options': <String>['低风', '高风', '爆炒'],
                  }),
              _e('sensor.viomi_left_status_p_6_5', left, name: '左灶'),
              _e('sensor.viomi_right_status_p_6_6', right, name: '右灶'),
            ],
          )!;

      expect(build('Off', 'Low').rightBurnerOn, isTrue);
      expect(build('Low', 'Big').leftBurnerOn, isTrue);
      expect(build('Low', 'Big').anyBurnerOn, isTrue);
      expect(build('Off', 'Off').anyBurnerOn, isFalse);
    });
  });
}

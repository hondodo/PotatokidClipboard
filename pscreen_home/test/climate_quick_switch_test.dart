import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/climate_quick_switch.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

HaEntityStateModel _e(String entityId, String state) => HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: const <String, dynamic>{},
    );

/// 米家空调（巨省电 m9）的典型 switch 子实体。
List<HaEntityStateModel> _acEntities() => <HaEntityStateModel>[
      _e('climate.xiaomi_cn_735376016_m9', 'cool'),
      _e('switch.xiaomi_cn_735376016_m9_eco_p_2_7', 'on'),
      _e('switch.xiaomi_cn_735376016_m9_heater_p_2_9', 'off'),
      _e('switch.xiaomi_cn_735376016_m9_sleep_mode_p_2_11', 'on'),
      _e('switch.xiaomi_cn_735376016_m9_un_straight_blowing_p_2_15', 'off'),
      _e('switch.xiaomi_cn_735376016_m9_favorite_on_p_2_19', 'off'),
      _e('switch.xiaomi_cn_735376016_m9_alarm_p_5_1', 'on'),
      _e('switch.xiaomi_cn_735376016_m9_run_dark_sleep_p_16_10', 'off'),
      // 非快捷开关的兄弟实体（不应被匹配）。
      _e('switch.xiaomi_cn_735376016_m9_dryer_p_2_10', 'off'),
      _e('sensor.xiaomi_cn_735376016_m9_filter_life_level', '101'),
    ];

void main() {
  group('ClimateQuickSwitch', () {
    test('按后缀匹配已知快捷开关，保持约定顺序与开关态', () {
      final List<ClimateQuickSwitch> list =
          ClimateQuickSwitch.buildList(_acEntities());

      expect(
        list.map((ClimateQuickSwitch s) => s.label).toList(),
        <String>['喜好', '节能', '睡眠', '辅热', '不直吹', '提示音', '熄屏'],
      );
      expect(
        list.firstWhere((ClimateQuickSwitch s) => s.label == '喜好').entityId,
        'switch.xiaomi_cn_735376016_m9_favorite_on_p_2_19',
      );
      expect(
        list.firstWhere((ClimateQuickSwitch s) => s.label == '节能').isOn,
        isTrue,
      );
      expect(
        list.firstWhere((ClimateQuickSwitch s) => s.label == '辅热').isOn,
        isFalse,
      );
      // 未列入快捷开关的实体不被匹配。
      expect(
        list.any((ClimateQuickSwitch s) =>
            s.entityId.endsWith('_dryer_p_2_10')),
        isFalse,
      );
    });

    test('无匹配实体返回空列表', () {
      expect(
        ClimateQuickSwitch.buildList(<HaEntityStateModel>[
          _e('switch.other_on_p_2_1', 'on'),
        ]),
        isEmpty,
      );
    });
  });
}

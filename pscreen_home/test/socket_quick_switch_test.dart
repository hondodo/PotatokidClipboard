import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/socket_quick_switch.dart';

HaEntityStateModel _e(String entityId, String state) => HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: const <String, dynamic>{},
    );

/// 米家智能插座 3（cuco v3）的典型实体。
List<HaEntityStateModel> _socketEntities() => <HaEntityStateModel>[
      _e('switch.cuco_cn_781304979_v3_on_p_2_1', 'on'),
      _e('switch.cuco_cn_781304979_v3_physical_controls_locked_p_7_1', 'on'),
      _e('switch.cuco_cn_781304979_v3_mode_p_3_2', 'off'),
      _e('light.cuco_cn_781304979_v3_s_13_indicator_light', 'on'),
      _e('sensor.cuco_cn_781304979_v3_electric_power_p_11_2', '24'),
    ];

void main() {
  group('SocketQuickSwitch', () {
    test('匹配童锁 / 定时（仅 switch 域），保持约定顺序与开关态', () {
      final List<SocketQuickSwitch> list =
          SocketQuickSwitch.buildList(_socketEntities());

      expect(
        list.map((SocketQuickSwitch s) => s.label).toList(),
        <String>['童锁', '定时'],
      );
      expect(list.first.label, '童锁');
      expect(list.first.isOn, isTrue);
      expect(list.last.label, '定时');
      expect(list.last.isOn, isFalse);
      // 主开关（_on_p_2_1）不应被当作快捷开关。
      expect(
        list.any((SocketQuickSwitch s) => s.entityId.endsWith('_on_p_2_1')),
        isFalse,
      );
    });

    test('指示灯（light 域）单独取 id 与开关态', () {
      expect(
        SocketQuickSwitch.indicatorLightEntityId(_socketEntities()),
        'light.cuco_cn_781304979_v3_s_13_indicator_light',
      );
      expect(SocketQuickSwitch.indicatorLightOn(_socketEntities()), isTrue);
    });

    test('无对应实体时 id 为 null、开关态为 false', () {
      final List<HaEntityStateModel> entities = <HaEntityStateModel>[
        _e('switch.other_on_p_2_1', 'on'),
      ];
      expect(SocketQuickSwitch.buildList(entities), isEmpty);
      expect(SocketQuickSwitch.indicatorLightEntityId(entities), isNull);
      expect(SocketQuickSwitch.indicatorLightOn(entities), isFalse);
    });
  });
}

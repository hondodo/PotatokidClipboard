import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';

HaEntityStateModel _e(
  String entityId,
  String state, {
  String? name,
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{'friendly_name': ?name},
    );

void main() {
  group('MultiSwitchSummary', () {
    test('解析左键 / 右键两路状态与短名称', () {
      final MultiSwitchSummary? summary = MultiSwitchSummary.tryBuild(
        deviceId: 'dev_switch',
        name: '小米米家智能开关（双开单控）',
        entities: <HaEntityStateModel>[
          _e('switch.zimi_on_p_2_1', 'off',
              name: '小米米家智能开关（双开单控） 客厅灯 左键'),
          _e('switch.zimi_on_p_3_1', 'on',
              name: '小米米家智能开关（双开单控） 右键-小米米家智能开关（双开单控） 右键'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.gangs.length, 2);
      expect(summary.gangs[0].label, '客厅灯');
      expect(summary.gangs[0].isOn, isFalse);
      expect(summary.gangs[1].label, '右键');
      expect(summary.gangs[1].isOn, isTrue);
      expect(summary.isAnyOn, isTrue);
      expect(summary.statusLabel, '客厅灯 关 · 右键 开');
    });

    test('只有一路开关时返回 null', () {
      final MultiSwitchSummary? summary = MultiSwitchSummary.tryBuild(
        deviceId: 'd',
        name: '插座',
        entities: <HaEntityStateModel>[
          _e('switch.plug_on_p_2_1', 'on', name: '插座'),
        ],
      );
      expect(summary, isNull);
    });
  });
}

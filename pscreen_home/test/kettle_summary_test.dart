import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';

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

List<HaEntityStateModel> _entities({String status = '待机中'}) =>
    <HaEntityStateModel>[
      _e('sensor.k_status_p_2_1', status, name: '热水瓶 工作状态'),
      _e('sensor.k_temperature_p_2_6', '51', name: '热水瓶 温度'),
      _e('sensor.k_fault_p_2_4', '无故障', name: '热水瓶 故障'),
      _e(
        'select.k_mode_p_2_3',
        '自来水',
        name: '热水瓶 模式',
        attributes: <String, dynamic>{
          'options': <String>['自来水', '纯净水', '凉白开'],
        },
      ),
      _e('number.k_target_temperature_p_2_5', '100', name: '热水瓶 设定温度'),
      _e('number.k_keep_warm_temperature_p_2_8', '55', name: '热水瓶 保温温度'),
      _e('switch.k_auto_keep_warm_p_2_7', 'on', name: '热水瓶 保温'),
      _e('switch.k_dechlorination_p_2_10', 'off', name: '热水瓶 除氯'),
      _e('switch.k_rapid_cooling_p_2_12', 'off', name: '热水瓶 风冷'),
      _e('binary_sensor.k_current_physical_control_lock_p_4_2', 'on', name: '童锁 物理控制锁状态'),
      _e(
        'select.k_lock_mode_p_4_3',
        '50℃及以上热水需要解锁',
        name: '童锁 模式',
        attributes: <String, dynamic>{
          'options': <String>[
            '50℃及以上热水需要解锁',
            '任意温度的水都不用解锁',
            '任意温度的水都需要解锁',
          ],
        },
      ),
      _e('notify.k_start_cook_a_2_1', 'unknown', name: '热水瓶 开始加热'),
      _e('button.k_cancel_cooking_a_2_2', 'unknown', name: '热水瓶 停止'),
    ];

void main() {
  group('KettleSummary', () {
    test('解析温度 / 状态 / 模式 / 参数 / 动作实体', () {
      final KettleSummary? summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '米家智能电热水瓶 5L',
        entities: _entities(),
      );

      expect(summary, isNotNull);
      expect(summary!.status, '待机中');
      expect(summary.temperature, 51);
      expect(summary.mode, '自来水');
      expect(summary.modes, <String>['自来水', '纯净水', '凉白开']);
      expect(summary.targetTemperature, 100);
      expect(summary.keepWarmTemperature, 55);
      expect(summary.keepWarmOn, isTrue);
      expect(summary.dechlorinationOn, isFalse);
      expect(summary.rapidCoolingOn, isFalse);
      expect(summary.childLocked, isTrue);
      expect(summary.lockMode, '50℃及以上热水需要解锁');
      expect(summary.targetEntityId, 'number.k_target_temperature_p_2_5');
      expect(summary.keepWarmEntityId, 'switch.k_auto_keep_warm_p_2_7');
      expect(summary.dechlorinationEntityId, 'switch.k_dechlorination_p_2_10');
      expect(summary.rapidCoolingEntityId, 'switch.k_rapid_cooling_p_2_12');
      expect(summary.startEntityId, 'notify.k_start_cook_a_2_1');
      expect(summary.stopEntityId, 'button.k_cancel_cooking_a_2_2');
      expect(summary.startMessage,
          '[M0, 100, true, 55, false, false, 66, 51]');
      expect(summary.isActive, isFalse);
      expect(summary.hasFault, isFalse);
    });

    test('烧水中处于活动状态，故障可识别', () {
      final KettleSummary summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(status: '烧水中…'),
      )!;
      expect(summary.isActive, isTrue);

      final KettleSummary faulty = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: <HaEntityStateModel>[
          ..._entities(),
          _e('sensor.k_fault2', '设备干烧', name: '热水瓶 故障'),
        ],
      )!;
      // 后一个故障实体不会被选中，仍为无故障
      expect(faulty.hasFault, isFalse);
    });

    test('缺少模式实体时不会误判成热水瓶', () {
      final KettleSummary? summary = KettleSummary.tryBuild(
        deviceId: 'dev_other',
        name: '普通插座',
        entities: <HaEntityStateModel>[
          _e('switch.other', 'off', name: '插座'),
        ],
      );
      expect(summary, isNull);
    });
  });
}

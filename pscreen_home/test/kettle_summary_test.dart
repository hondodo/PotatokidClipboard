import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';

HaEntityStateModel _e(
  String entityId,
  String state, {
  String? name,
  Map<String, dynamic> attributes = const <String, dynamic>{},
  DateTime? lastChanged,
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{
        'friendly_name': ?name,
        ...attributes,
      },
      lastChanged: lastChanged,
    );

List<HaEntityStateModel> _entities({
  String status = '待机中',
  String mode = '自来水',
}) =>
    <HaEntityStateModel>[
      _e('sensor.k_status_p_2_1', status, name: '热水瓶 工作状态'),
      _e('sensor.k_temperature_p_2_6', '51', name: '热水瓶 温度'),
      _e('sensor.k_fault_p_2_4', '无故障', name: '热水瓶 故障'),
      _e(
        'select.k_mode_p_2_3',
        mode,
        name: '热水瓶 模式',
        attributes: <String, dynamic>{
          'options': <String>['自来水', '纯净水', '凉白开'],
        },
      ),
      _e('number.k_target_temperature_p_2_5', '100', name: '热水瓶 设定温度'),
      _e('number.k_keep_warm_temperature_p_2_8', '55', name: '热水瓶 保温温度'),
      _e('number.k_keep_warm_temperature_p_2_13', '66',
          name: '热水瓶 纯净水保温温度'),
      _e('number.k_keep_warm_temperature_p_2_14', '51',
          name: '热水瓶 自来水保温温度'),
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
          '[M0, 100, true, 51, false, false, 66, 51]');
      expect(summary.effectiveTargetTemperature, 100);
      expect(summary.effectiveKeepWarmTemperature, 51);
      expect(summary.showDechlorination, isTrue);
      expect(summary.showKeepWarmSwitch, isFalse);
      expect(summary.isActive, isFalse);
      expect(summary.hasFault, isFalse);
      expect(summary.cardActionLabel, '加热');
      expect(summary.stopLabel, '停止加热');
    });

    test('烧水中处于活动状态，故障可识别', () {
      final KettleSummary summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(status: '烧水中…'),
      )!;
      expect(summary.isActive, isTrue);
      expect(summary.stopLabel, '停止加热');
      expect(summary.cardActionLabel, '停止加热');

      final KettleSummary warming = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(status: '保温中…'),
      )!;
      expect(warming.stopLabel, '停止保温');
      expect(warming.cardActionLabel, '停止保温');

      final KettleSummary cooling = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(status: '降温中…'),
      )!;
      expect(cooling.stopLabel, '停止保温');

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

    test('纯净水模式：目标温度取纯净水保温温度 66℃', () {
      final KettleSummary summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(mode: '纯净水'),
      )!;
      expect(summary.isPureWater, isTrue);
      expect(summary.effectiveTargetTemperature, 66);
      expect(summary.effectiveKeepWarmTemperature, 66);
      expect(summary.showDechlorination, isFalse);
      expect(summary.showKeepWarmSwitch, isTrue);
      expect(summary.startMessage,
          '[M0, 66, true, 66, false, false, 66, 51]');
    });

    test('凉白开模式：不显示保温和保温温度', () {
      final KettleSummary summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities(mode: '凉白开'),
      )!;
      expect(summary.isBoiledWater, isTrue);
      expect(summary.showDechlorination, isTrue);
      expect(summary.showKeepWarmSwitch, isFalse);
      expect(summary.showKeepWarmTemperature, isFalse);
    });

    test('离线：状态显示离线、温度 --、不误报故障、时长取最早 last_changed', () {
      final DateTime now = DateTime.utc(2026, 10, 23, 12);
      final DateTime since = now.subtract(const Duration(days: 4, hours: 1));
      final KettleSummary summary = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: <HaEntityStateModel>[
          _e('sensor.k_status_p_2_1', 'unavailable', lastChanged: since),
          _e(
            'sensor.k_temperature_p_2_6',
            'unavailable',
            lastChanged: since.add(const Duration(minutes: 2)),
          ),
          _e(
            'select.k_mode_p_2_3',
            'unavailable',
            attributes: <String, dynamic>{
              'options': <String>['自来水', '纯净水', '凉白开'],
            },
            lastChanged: since.add(const Duration(minutes: 5)),
          ),
          _e('sensor.k_fault_p_2_4', 'unavailable', lastChanged: since),
          // notify / button 正常态就是 unknown，不能把它们的旧时间当成离线起点
          _e(
            'notify.k_start_cook_a_2_1',
            'unknown',
            lastChanged: since.subtract(const Duration(days: 30)),
          ),
        ],
      )!;

      expect(summary.isOffline, isTrue);
      expect(summary.statusLabel, '离线');
      expect(summary.temperatureLabel, '--');
      expect(summary.modeLabel, '--');
      expect(summary.hasFault, isFalse);
      expect(summary.isActive, isFalse);
      expect(summary.offlineDuration(now), const Duration(days: 4, hours: 1));
      expect(summary.offlineLabel(now: now), '已离线 4 天');
    });

    test('故障实体为 unavailable / unknown 时不算故障', () {
      final KettleSummary unavailable = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities().map((HaEntityStateModel entity) {
          if (entity.entityId.contains('_fault_')) {
            return _e(entity.entityId, 'unavailable');
          }
          return entity;
        }).toList(growable: false),
      )!;
      expect(unavailable.isOffline, isFalse);
      expect(unavailable.hasFault, isFalse);

      final KettleSummary unknown = KettleSummary.tryBuild(
        deviceId: 'dev_k',
        name: '热水瓶',
        entities: _entities().map((HaEntityStateModel entity) {
          if (entity.entityId.contains('_fault_')) {
            return _e(entity.entityId, 'unknown');
          }
          return entity;
        }).toList(growable: false),
      )!;
      expect(unknown.hasFault, isFalse);
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

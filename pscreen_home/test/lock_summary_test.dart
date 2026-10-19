import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/lock_summary.dart';

/// 实测的鹿客门锁实体（截取自 HA 的 get_states 日志）。
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

const String _doorStateId =
    'sensor.loock_cn_1170332313_t2pv1_door_state_p_3_1021';
const String _batteryId =
    'sensor.loock_cn_1170332313_t2pv1_battery_level_p_4_1003';
const String _catEyeBatteryId =
    'sensor.loock_cn_1170332313_t2pv1_battery_level_p_10_1';
const String _batteryUpdateId =
    'sensor.loock_cn_1170332313_t2pv1_battery_update_time_p_11_15';
const String _onlineTimestampId =
    'sensor.loock_cn_1170332313_t2pv1_online_timestamp_p_11_17';

List<HaEntityStateModel> _lockEntities({String doorState = '已上锁'}) =>
    <HaEntityStateModel>[
      _e(
        _doorStateId,
        doorState,
        name: '门锁 门 门状态（按bite位复用）',
        attributes: <String, dynamic>{'device_class': 'enum'},
      ),
      _e(
        _batteryId,
        '39',
        name: '门锁 电池 电池电量',
        attributes: <String, dynamic>{
          'device_class': 'battery',
          'unit_of_measurement': '%',
        },
      ),
      _e(
        _catEyeBatteryId,
        '97',
        name: '门锁 猫眼电池 电池电量',
        attributes: <String, dynamic>{
          'device_class': 'battery',
          'unit_of_measurement': '%',
        },
      ),
      _e(
        _batteryUpdateId,
        '1792414663',
        name: '门锁 * WIFI自定义服务 摄像头锂电池电量更新时间戳',
        attributes: <String, dynamic>{'unit_of_measurement': 's'},
      ),
      _e(
        _onlineTimestampId,
        '1792414700',
        name: '门锁 * WIFI自定义服务 设备联网上线的时间戳',
        attributes: <String, dynamic>{'unit_of_measurement': 's'},
      ),
      _e(
        'switch.loock_cn_1170332313_t2pv1_on_p_7_1',
        'on',
        name: '门锁 可视门铃 开关-移动侦测开关',
        attributes: <String, dynamic>{'device_class': 'switch'},
      ),
    ];

void main() {
  group('LockSummary', () {
    test('按真实 id 解析上锁状态、两块电池、电量更新时间', () {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: '80899ffab39bcea97f969e28bd806559',
        name: '门锁',
        entities: _lockEntities(),
      );

      expect(summary, isNotNull);
      expect(summary!.locked, isTrue);
      expect(summary.statusLabel, '已上锁');
      expect(summary.stateEntityId, _doorStateId);

      expect(summary.batteries, hasLength(2));
      expect(
        summary.batteries.map((LockBattery b) => b.label),
        <String>['电池', '猫眼电池'],
      );
      expect(
        summary.batteries.map((LockBattery b) => b.percent),
        <int>[39, 97],
      );
      expect(summary.batteries.first.valueLabel, '39%');
      expect(summary.batteries.last.valueLabel, '97%');

      final DateTime expected =
          DateTime.fromMillisecondsSinceEpoch(1792414663 * 1000);
      expect(summary.batteryUpdatedAt, expected);
      expect(summary.batteryUpdateEntityId, _batteryUpdateId);
      // 联网时间戳不能被当成电量更新时间。
      expect(summary.batteryUpdateEntityId, isNot(_onlineTimestampId));

      // 详情页需要隐藏：上锁状态 + 两块电池 + 电量更新时间。
      expect(
        summary.infoEntityIds,
        containsAll(<String>[
          _doorStateId,
          _batteryId,
          _catEyeBatteryId,
          _batteryUpdateId,
        ]),
      );
      expect(summary.infoEntityIds, isNot(contains(_onlineTimestampId)));
    });

    test('未上锁状态解析为 false', () {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: 'dev_lock',
        name: '门锁',
        entities: _lockEntities(doorState: '未上锁'),
      );

      expect(summary, isNotNull);
      expect(summary!.locked, isFalse);
      expect(summary.statusLabel, '未上锁');
    });

    test('没有门状态实体时不当作门锁（即使带电池）', () {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: 'dev_washer',
        name: '洗衣机',
        entities: <HaEntityStateModel>[
          _e(
            'sensor.washer_battery_level_p_1_1',
            '80',
            name: '洗衣机 电池 电池电量',
            attributes: <String, dynamic>{
              'device_class': 'battery',
              'unit_of_measurement': '%',
            },
          ),
        ],
      );

      expect(summary, isNull);
    });

    test('洗衣机等家电的门状态传感器不会被误判成门锁', () {
      // 来自 washer_summary_test：sensor.wm_door_state_p_2_9 = 舱门已开
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: 'dev_wm',
        name: '米家洗衣机 洗烘12kg',
        entities: <HaEntityStateModel>[
          _e('sensor.wm_status_p_2_2', '已关机', name: '洗衣机 工作状态'),
          _e('sensor.wm_door_state_p_2_9', '舱门已开', name: '洗衣机 门状态'),
          _e('sensor.wm_power_consumption_p_2_39', '14', name: '洗衣机 耗电量'),
          _e('switch.wm_on_p_2_1', 'off', name: '洗衣机 洗衣机 开关'),
        ],
      );

      expect(summary, isNull);
    });

    test('id 像门锁但状态是 on/off 的二进制传感器不被当作门锁', () {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: 'dev_generic',
        name: '某设备',
        entities: <HaEntityStateModel>[
          _e('binary_sensor.generic_lock_state_p_1_1', 'off'),
        ],
      );

      expect(summary, isNull);
    });

    test('只有联网时间戳时，不生成电量更新时间', () {
      final LockSummary? summary = LockSummary.tryBuild(
        deviceId: 'dev_lock',
        name: '门锁',
        entities: <HaEntityStateModel>[
          _e(_doorStateId, '已上锁'),
          _e(
            _onlineTimestampId,
            '1792414700',
            attributes: <String, dynamic>{'unit_of_measurement': 's'},
          ),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.batteryUpdatedAt, isNull);
      expect(summary.batteryUpdateEntityId, isNull);
      expect(summary.batteryUpdatedLabel, isNull);
    });
  });
}

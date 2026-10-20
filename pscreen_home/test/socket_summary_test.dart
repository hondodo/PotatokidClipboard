import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';

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

List<HaEntityStateModel> _socketEntities({String fault = '无故障'}) =>
    <HaEntityStateModel>[
      _e('switch.cuco_on_p_2_1', 'on', name: '插座 开关'),
      _e('sensor.cuco_electric_power_p_11_2', '0', name: '当前功率'),
      _e('sensor.cuco_power_consumption_p_11_1', '0.01', name: '累计电量'),
      _e('sensor.cuco_temperature_p_12_2', '46', name: '设备温度'),
      _e('sensor.cuco_on_off_count_p_12_1', '3', name: '开关次数'),
      _e('sensor.cuco_fault_p_2_3', fault, name: '故障'),
    ];

void main() {
  group('SocketSummary', () {
    test('解析开关 / 当前功率 / 累计电量 / 温度 / 次数', () {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: 'dev_socket',
        name: '阳台植物灯',
        entities: _socketEntities(),
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isTrue);
      expect(summary.statusLabel, '已开启');
      expect(summary.stats.currentWatts, 0);
      expect(summary.stats.currentPowerLabel, '0 W');
      expect(summary.stats.totalKwh, 0.01);
      expect(summary.stats.totalLabel, '0.01 kWh');
      expect(summary.stats.deviceTemperature, 46);
      expect(summary.stats.switchCount, 3);
      expect(summary.hasFault, isFalse);
    });

    test('故障值为 0 视为无故障', () {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: 'dev_socket',
        name: '阳台植物灯',
        entities: _socketEntities(fault: '0'),
      );

      expect(summary, isNotNull);
      expect(summary!.hasFault, isFalse);
      expect(summary.statusLabel, '已开启');
    });

    test('空调设备不会被当作智能插座', () {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: 'dev_ac',
        name: '小米空调',
        entities: <HaEntityStateModel>[
          _e('climate.xiaomi_cn_735376016_m9', 'cool', name: '空调'),
          _e('switch.xiaomi_cn_735376016_m9_favorite_on_p_2_19', 'off',
              name: '收藏'),
          _e('sensor.xiaomi_cn_735376016_m9_electric_power_p_12_13_14',
              '1423.8',
              name: '外机功率'),
          _e('sensor.xiaomi_cn_735376016_m9_power_consumption_p_20_1',
              '1859.3',
              name: '累计电量'),
          _e('sensor.xiaomi_cn_735376016_m9_fault_p_2_3', '0', name: '故障'),
        ],
      );

      expect(summary, isNull);
    });

    test('收藏开关不会被当作插座电源', () {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: 'dev_other',
        name: '收藏开关设备',
        entities: <HaEntityStateModel>[
          _e('switch.demo_favorite_on_p_2_19', 'off', name: '收藏'),
          _e('sensor.demo_electric_power_p_11_2', '12', name: '当前功率'),
        ],
      );

      expect(summary, isNull);
    });

    test('只有电量没有当前功率的开关设备不当作智能插座', () {
      final SocketSummary? summary = SocketSummary.tryBuild(
        deviceId: 'dev_other',
        name: '洗衣机',
        entities: <HaEntityStateModel>[
          _e('switch.wm_on_p_2_1', 'off', name: '电源'),
          _e('sensor.wm_power_consumption_p_2_39', '14', name: '耗电量'),
        ],
      );
      expect(summary, isNull);
    });
  });

  group('PowerStats', () {
    test('空调插座只有当前功率，没有累计电量', () {
      final PowerStats? stats = PowerStats.tryBuild(<HaEntityStateModel>[
        _e('sensor.lumi_electric_power_p_5_1', '1.46', name: '电功率'),
      ]);
      expect(stats, isNotNull);
      expect(stats!.currentPowerLabel, '1.5 W');
      expect(stats.totalKwh, isNull);
      expect(stats.totalLabel, '—');
    });

    test('空调外机功率按 _ac_power_ 解析', () {
      final PowerStats? stats = PowerStats.tryBuild(<HaEntityStateModel>[
        _e('sensor.xiaomi_cn_735376016_m9_outdoor_ac_power_p_12_1314',
            '1423.8',
            name: '空调外机功率'),
        _e('sensor.xiaomi_cn_735376016_m9_power_consumption_p_20_1', '1859.3',
            name: '累计电量'),
      ]);
      expect(stats, isNotNull);
      expect(stats!.acPowerWatts, 1423.8);
      expect(stats.acPowerEntityId,
          'sensor.xiaomi_cn_735376016_m9_outdoor_ac_power_p_12_1314');
      expect(stats.currentWatts, isNull);
      expect(stats.currentPowerLabel, '1424 W');
      expect(stats.totalKwh, 1859.3);
      expect(stats.hasData, isTrue);
    });
  });
}

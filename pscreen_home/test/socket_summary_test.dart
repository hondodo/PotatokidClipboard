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

List<HaEntityStateModel> _socketEntities() => <HaEntityStateModel>[
      _e('switch.cuco_on_p_2_1', 'on', name: '插座 开关'),
      _e('sensor.cuco_electric_power_p_11_2', '0', name: '当前功率'),
      _e('sensor.cuco_power_consumption_p_11_1', '0.01', name: '累计电量'),
      _e('sensor.cuco_temperature_p_12_2', '46', name: '设备温度'),
      _e('sensor.cuco_on_off_count_p_12_1', '3', name: '开关次数'),
      _e('sensor.cuco_fault_p_2_3', '无故障', name: '故障'),
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
  });
}

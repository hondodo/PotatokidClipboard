import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/water_purifier_summary.dart';

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
  group('WaterPurifierSummary', () {
    test('解析 TDS / 水温 / 两枚滤芯 / 模式开关', () {
      final WaterPurifierSummary? summary =
          WaterPurifierSummary.tryBuild(
        deviceId: 'dev_purifier',
        name: '米家净水器S1 1200G',
        entities: <HaEntityStateModel>[
          _e('sensor.pur_status_p_2_2', '待机中', name: '状态'),
          _e('sensor.pur_tds_out_p_4_2', '60', name: 'TDS'),
          _e('sensor.pur_temperature_p_2_3', '30', name: '水温'),
          _e('sensor.pur_fault_p_2_1', '0', name: '故障'),
          _e('sensor.pur_filter_life_level_p_3_1', '45', name: 'PPC寿命'),
          _e('sensor.pur_filter_left_time_p_3_2', '324', name: 'PPC天数'),
          _e('sensor.pur_filter_life_level_p_5_1', '78', name: 'RO寿命'),
          _e('sensor.pur_filter_left_time_p_5_2', '1419', name: 'RO天数'),
          _e('switch.pur_holiday_mode_p_2_7', 'on', name: '假期模式'),
          _e('switch.pur_pipeline_connection_p_2_5', 'off', name: '管线机'),
          _e('switch.pur_alarm_p_9_1', 'off', name: '提示音'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.status, '待机中');
      expect(summary.tds, 60);
      expect(summary.temperature, 30);
      expect(summary.hasFault, isFalse);
      expect(summary.filters.length, 2);
      expect(summary.filters[0].name, 'PPC复合滤芯');
      expect(summary.filters[0].lifePercent, 45);
      expect(summary.filters[0].leftDays, 324);
      expect(summary.filters[1].name, 'RO反渗透滤芯');
      expect(summary.filters[1].lifePercent, 78);
      expect(summary.holidayMode, isTrue);
      expect(summary.pipelineConnected, isFalse);
    });

    test('不是净水器时返回 null', () {
      final WaterPurifierSummary? summary =
          WaterPurifierSummary.tryBuild(
        deviceId: 'd',
        name: 'fridge',
        entities: <HaEntityStateModel>[
          _e('sensor.x_status_p_2_2', '待机中', name: '状态'),
        ],
      );
      expect(summary, isNull);
    });
  });
}

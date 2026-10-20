import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';

HaEntityStateModel e(String id, {Map<String, dynamic>? attributes}) =>
    HaEntityStateModel(
      entityId: id,
      state: '1',
      attributes: attributes ?? const <String, dynamic>{},
    );

void main() {
  test('功率取 _electric_power_ sensor', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd1',
      title: '插座',
      entities: <HaEntityStateModel>[e('sensor.d1_electric_power_p_5_1')],
    );
    expect(MetricEntityResolver.resolve(group)[Metric.power],
        'sensor.d1_electric_power_p_5_1');
  });

  test('温度取 sensor._temperature_ 实体，湿度取 _humidity_ 实体', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2',
      title: '冰箱',
      entities: <HaEntityStateModel>[
        e('sensor.midjd_temperature_p_3_1'),
        e('sensor.midjd_environment_humidity_p_10_10'),
      ],
    );
    final Map<Metric, String> resolved = MetricEntityResolver.resolve(group);
    expect(resolved[Metric.temperature], 'sensor.midjd_temperature_p_3_1');
    expect(resolved[Metric.humidity],
        'sensor.midjd_environment_humidity_p_10_10');
  });

  test('number.* 目标温度与 climate 属性不参与（无时间序列可查）', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2b',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('number.d2b_target_temperature_p_2_5'),
        e('climate.d2b', attributes: <String, dynamic>{
          'current_temperature': 26.0,
          'current_humidity': 55,
        }),
      ],
    );
    expect(MetricEntityResolver.resolve(group), isEmpty);
  });

  test('无对应实体时该 metric 缺失', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd3',
      title: '灯',
      entities: <HaEntityStateModel>[e('light.d3')],
    );
    final Map<Metric, String> resolved = MetricEntityResolver.resolve(group);
    expect(resolved.containsKey(Metric.power), isFalse);
    expect(resolved.containsKey(Metric.temperature), isFalse);
    expect(resolved.containsKey(Metric.humidity), isFalse);
  });
}

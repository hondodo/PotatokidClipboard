import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';

HaEntityStateModel e(
  String id, {
  String state = '1',
  Map<String, dynamic>? attributes,
}) =>
    HaEntityStateModel(
      entityId: id,
      state: state,
      attributes: attributes ?? const <String, dynamic>{},
    );

void main() {
  test('功率取 _electric_power_ sensor', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd1',
      title: '插座',
      entities: <HaEntityStateModel>[e('sensor.d1_electric_power_p_5_1')],
    );
    expect(MetricEntityResolver.resolve(group)[Metric.power]?.entityId,
        'sensor.d1_electric_power_p_5_1');
  });

  test('空调外机功率 _ac_power_ 优先于 _electric_power_', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd1b',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('sensor.ac_electric_power_p_2_1'),
        e('sensor.ac_outdoor_ac_power_p_12_1314'),
      ],
    );
    expect(MetricEntityResolver.resolve(group)[Metric.power]?.entityId,
        'sensor.ac_outdoor_ac_power_p_12_1314');
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
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolve(group);
    expect(resolved[Metric.temperature]?.entityId,
        'sensor.midjd_temperature_p_3_1');
    expect(resolved[Metric.humidity]?.entityId,
        'sensor.midjd_environment_humidity_p_10_10');
  });

  test('空调回退 climate 属性（仅内存曲线）', () {
    final HaEntityStateModel climate = e(
      'climate.d2b',
      state: 'cool',
      attributes: <String, dynamic>{
        'current_temperature': 26.0,
        'current_humidity': 55,
      },
    );
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2b',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('number.d2b_target_temperature_p_2_5'),
        climate,
      ],
    );
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolve(group);

    expect(resolved.containsKey(Metric.power), isFalse);
    expect(resolved[Metric.temperature]?.attribute, 'current_temperature');
    expect(resolved[Metric.humidity]?.attribute, 'current_humidity');
    expect(resolved[Metric.temperature]?.isAttribute, isTrue);
    expect(resolved[Metric.temperature]?.valueOf(climate), 26.0);
  });

  test('同设备温度 sensor 优先于 climate 属性', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2c',
      title: '空调',
      entities: <HaEntityStateModel>[
        e(
          'climate.d2c',
          state: 'heat',
          attributes: <String, dynamic>{'current_temperature': 26.0},
        ),
        e('sensor.d2c_temperature_p_1_1', state: '25.3'),
      ],
    );
    final MetricSource source =
        MetricEntityResolver.resolve(group)[Metric.temperature]!;

    expect(source.entityId, 'sensor.d2c_temperature_p_1_1');
    expect(source.isAttribute, isFalse);
  });

  test('climate 缺少属性时不产生来源', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2d',
      title: '空调',
      entities: <HaEntityStateModel>[e('climate.d2d', state: 'off')],
    );
    expect(MetricEntityResolver.resolve(group), isEmpty);
  });

  test('词元匹配也接受结尾命名（template sensor）', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2e',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('sensor.ac_h09h00_temperature'),
        e('sensor.ac_h09h00_humidity'),
      ],
    );
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolve(group);
    expect(resolved[Metric.temperature]?.entityId,
        'sensor.ac_h09h00_temperature');
    expect(resolved[Metric.humidity]?.entityId, 'sensor.ac_h09h00_humidity');
    expect(resolved[Metric.temperature]?.isAttribute, isFalse);
  });

  test('按 device_class 识别命名不规范的 sensor', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2f',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('sensor.kong_diao_wen_du', attributes: <String, dynamic>{
          'device_class': 'temperature',
        }),
        e('sensor.kong_diao_shi_du', attributes: <String, dynamic>{
          'device_class': 'humidity',
        }),
      ],
    );
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolve(group);
    expect(resolved[Metric.temperature]?.entityId, 'sensor.kong_diao_wen_du');
    expect(resolved[Metric.humidity]?.entityId, 'sensor.kong_diao_shi_du');
  });

  test('命名约定优先于 device_class', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2g',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('sensor.other_wen_du', attributes: <String, dynamic>{
          'device_class': 'temperature',
        }),
        e('sensor.ac_temperature'),
      ],
    );
    expect(
      MetricEntityResolver.resolve(group)[Metric.temperature]?.entityId,
      'sensor.ac_temperature',
    );
  });

  test('humidity_range 之类派生 sensor 不会抢走真正的湿度计', () {
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolveEntities(<HaEntityStateModel>[
      e('sensor.ac_humidity_range_p_10_6', state: '40-70'),
      e('sensor.ac_humidity', state: '56'),
    ]);
    expect(resolved[Metric.humidity]?.entityId, 'sensor.ac_humidity');
  });

  test('device_class 优先于命名里夹带的词元', () {
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolveEntities(<HaEntityStateModel>[
      e('sensor.ac_humidity_range_p_10_6', state: '40-70'),
      e(
        'sensor.kong_diao_shi_du',
        state: '56',
        attributes: <String, dynamic>{'device_class': 'humidity'},
      ),
    ]);
    expect(resolved[Metric.humidity]?.entityId, 'sensor.kong_diao_shi_du');
  });

  test('无对应实体时该 metric 缺失', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd3',
      title: '灯',
      entities: <HaEntityStateModel>[e('light.d3')],
    );
    final Map<Metric, MetricSource> resolved =
        MetricEntityResolver.resolve(group);
    expect(resolved.containsKey(Metric.power), isFalse);
    expect(resolved.containsKey(Metric.temperature), isFalse);
    expect(resolved.containsKey(Metric.humidity), isFalse);
  });
}

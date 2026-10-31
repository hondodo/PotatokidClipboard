import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

void main() {
  test('Metric 三指标', () {
    expect(Metric.values, <Metric>[
      Metric.power,
      Metric.temperature,
      Metric.humidity,
    ]);
  });

  test('MetricSample 承载 value 与可选 min/max', () {
    final DateTime at = DateTime(2026, 1, 1, 12);
    final MetricSample point = MetricSample(at: at, value: 123.5);
    expect(point.at, at);
    expect(point.value, 123.5);
    expect(point.min, isNull);
    expect(point.max, isNull);

    final MetricSample stat = MetricSample(
      at: DateTime(2026, 1, 1, 12),
      value: 20,
      min: 10,
      max: 30,
    );
    expect(stat.min, 10);
    expect(stat.max, 30);
  });

  test('Metric 展示信息', () {
    expect(Metric.power.label, '功率');
    expect(Metric.power.unit, 'W');
    expect(Metric.temperature.label, '温度');
    expect(Metric.temperature.unit, '°C');
    expect(Metric.humidity.label, '湿度');
    expect(Metric.humidity.unit, '%');
  });
}

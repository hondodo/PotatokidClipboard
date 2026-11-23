/// 指标类型。
enum Metric { power, temperature, humidity }

/// 指标展示信息。
extension MetricInfo on Metric {
  String get label => switch (this) {
        Metric.power => '功率',
        Metric.temperature => '温度',
        Metric.humidity => '湿度',
      };

  String get unit => switch (this) {
        Metric.power => 'W',
        Metric.temperature => '°C',
        Metric.humidity => '%',
      };
}

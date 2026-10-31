/// 一个采样点：时刻 + 值（功率 W / 温度 °C / 湿度 %）。
///
/// 明细曲线只有 [value]；统计聚合曲线用 [value] 存均值，
/// [min] / [max] 存区间最小 / 最大值（用于 y 轴范围，可选）。
class MetricSample {
  const MetricSample({
    required this.at,
    required this.value,
    this.min,
    this.max,
  });

  final DateTime at;
  final double value;
  final double? min;
  final double? max;
}

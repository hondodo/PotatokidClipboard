/// 一个家庭的温湿度概览。
///
/// HA 没有「全屋温度」这种聚合实体，温度 / 湿度实际来自该家庭内某台
/// 空调（climate）的 `current_temperature` / `current_humidity` 属性。
/// [sourceName] 记录取值设备，便于界面标注数据来源。
class HomeClimateSummary {
  const HomeClimateSummary({
    required this.homeName,
    this.temperature,
    this.humidity,
    this.sourceName,
  });

  /// 家庭名（区域名前缀）
  final String homeName;

  /// 当前温度（℃），缺失为 null
  final double? temperature;

  /// 当前湿度（%），缺失为 null
  final int? humidity;

  /// 温湿度来源设备名
  final String? sourceName;

  /// 是否至少有一项数据
  bool get hasData => temperature != null || humidity != null;

  @override
  String toString() =>
      'HomeClimateSummary($homeName, $temperature, $humidity, $sourceName)';
}

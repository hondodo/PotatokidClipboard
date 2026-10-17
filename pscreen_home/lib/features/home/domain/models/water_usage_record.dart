/// 一条热水器用水记录（HA `event.*_usage_record` 的历史条目）。
class WaterUsageRecord {
  const WaterUsageRecord({
    required this.timestamp,
    required this.waterLiters,
    required this.gasCubicMeters,
    required this.seconds,
    required this.temperature,
  });

  final DateTime timestamp;
  final double waterLiters;
  final double gasCubicMeters;
  final int seconds;
  final double temperature;

  /// 从 WS `history/history_during_period` 的结果项解析。
  ///
  /// HA 返回的紧凑结构为 `{s: 状态, a: 属性, lu: 时间戳}`；非「使用记录」
  /// 事件（初始化时的 unknown）返回 null。
  static WaterUsageRecord? fromHistoryItem(Map<String, dynamic> item) {
    final Object? rawState = item['s'];
    final Object? rawAttributes = item['a'];
    if (rawState is! String || rawAttributes is! Map) return null;
    final DateTime? timestamp = DateTime.tryParse(rawState);
    if (timestamp == null) return null;
    final Map<String, dynamic> attributes =
        Map<String, dynamic>.from(rawAttributes);
    if (attributes['event_type'] != '使用记录') return null;

    return WaterUsageRecord(
      timestamp: timestamp.toLocal(),
      waterLiters: _num(attributes['耗水量']),
      gasCubicMeters: _num(attributes['耗气量（立方米）']),
      seconds: _num(attributes['已使用时间']).round(),
      temperature: _num(attributes['温度']),
    );
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

/// 历史曲线时间范围。
enum HistoryRange {
  h1('1h', Duration(hours: 1)),
  h6('6h', Duration(hours: 6)),
  h12('12h', Duration(hours: 12)),
  h24('24h', Duration(hours: 24)),
  week('周', Duration(days: 7)),
  month('月', Duration(days: 30)),
  year('年', Duration(days: 365));

  const HistoryRange(this.label, this.duration);

  final String label;
  final Duration duration;

  /// 是否走明细（≤7 天）；否则走长期统计。
  bool get useDetailed => duration <= const Duration(days: 7);

  /// 统计周期：≤60 天用 hour，否则 day。
  String get statPeriod =>
      duration <= const Duration(days: 60) ? 'hour' : 'day';
}

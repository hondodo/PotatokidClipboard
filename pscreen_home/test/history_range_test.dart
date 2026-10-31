import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';

void main() {
  test('各 range 的标签与时长', () {
    expect(HistoryRange.h1.label, '1h');
    expect(HistoryRange.h1.duration, const Duration(hours: 1));
    expect(HistoryRange.week.label, '周');
    expect(HistoryRange.week.duration, const Duration(days: 7));
    expect(HistoryRange.year.duration, const Duration(days: 365));
  });

  test('≤7 天走明细，>7 天走统计', () {
    expect(HistoryRange.h24.useDetailed, isTrue);
    expect(HistoryRange.week.useDetailed, isTrue);
    expect(HistoryRange.month.useDetailed, isFalse);
    expect(HistoryRange.year.useDetailed, isFalse);
  });

  test('统计周期：≤60 天 hour，否则 day', () {
    expect(HistoryRange.month.statPeriod, 'hour');
    expect(HistoryRange.year.statPeriod, 'day');
  });
}

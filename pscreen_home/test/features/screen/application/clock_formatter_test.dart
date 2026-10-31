import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';

void main() {
  group('formatClockTime', () {
    final DateTime now = DateTime(2026, 10, 21, 21, 5, 3);

    test('带秒时输出 HH:mm:ss', () {
      expect(formatClockTime(now), '21:05:03');
    });

    test('不带秒时输出 HH:mm', () {
      expect(formatClockTime(now, withSeconds: false), '21:05');
    });

    test('小时补零', () {
      expect(
        formatClockTime(DateTime(2026, 1, 2, 3, 4, 5)),
        '03:04:05',
      );
    });
  });

  group('formatClockDate', () {
    test('输出年月日与星期', () {
      expect(
        formatClockDate(DateTime(2026, 10, 21)),
        '2026年10月21日 星期三',
      );
    });
  });

  group('formatLunarLine', () {
    test('输出农历日期', () {
      final String line = formatLunarLine(DateTime(2026, 10, 21));
      expect(line, isNotEmpty);
      expect(line, contains('月'));
    });

    test('超出农历表范围时返回空串', () {
      expect(formatLunarLine(DateTime(1850, 1, 1)), '');
    });
  });
}

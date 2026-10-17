import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_schedule.dart';
import 'package:pscreen_home/features/home/domain/models/water_usage_record.dart';

const String _sample =
    '0&2315&2316&0&0-0&0000&0000&0&9-0&0000&0000&0&9'
    '-0&0000&0000&0&9-0&0000&0000&0&9';

void main() {
  group('PreheatSchedule', () {
    test('解析 5 个槽位与当前 23:15-23:16 仅一次', () {
      final PreheatSchedule schedule = PreheatSchedule.parse(_sample);
      expect(schedule.slots.length, 5);

      final PreheatSlot first = schedule.slots.first;
      expect(first.repeat, PreheatRepeat.once);
      expect(first.startMinutes, 23 * 60 + 15);
      expect(first.endMinutes, 23 * 60 + 16);
      expect(first.enabled, isFalse);
      expect(first.id, 0);
      expect(first.isEmpty, isFalse);

      expect(schedule.slots[1].isEmpty, isTrue);
      expect(schedule.slots[1].id, 9);
    });

    test('编码可往返，开关改为 1', () {
      final PreheatSchedule parsed = PreheatSchedule.parse(_sample);
      expect(parsed.encode(), _sample);

      final PreheatSchedule enabled = parsed.replace(
        0,
        parsed.slots.first.copyWith(enabled: true),
      );
      expect(enabled.encode(), contains('0&2315&2316&1&0'));
    });

    test('每天使用 everyday token', () {
      final PreheatSchedule schedule = PreheatSchedule.parse(
        'everyday&1820&1920&1&1-0&0000&0000&0&9-0&0000&0000&0&9'
        '-0&0000&0000&0&9-0&0000&0000&0&9',
      );
      expect(schedule.slots.first.repeat, PreheatRepeat.daily);
      expect(schedule.slots.first.label, '18:20–19:20 · 每天');
    });

    test('非法 / 缺省槽位回退为空', () {
      final PreheatSchedule schedule = PreheatSchedule.parse('bad');
      expect(schedule.slots.length, 5);
      expect(schedule.slots.every((PreheatSlot s) => s.isEmpty), isTrue);
    });
  });

  group('WaterUsageRecord', () {
    test('解析历史项属性', () {
      final WaterUsageRecord? record = WaterUsageRecord.fromHistoryItem(
        <String, dynamic>{
          's': '2026-10-17T14:51:17.766+00:00',
          'a': <String, dynamic>{
            'event_type': '使用记录',
            '耗水量': 25.2,
            '耗气量（立方米）': 0.034,
            '已使用时间': 304,
            '温度': 40,
          },
        },
      );
      expect(record, isNotNull);
      expect(record!.waterLiters, 25.2);
      expect(record.gasCubicMeters, 0.034);
      expect(record.seconds, 304);
      expect(record.temperature, 40);
      expect(record.timestamp.isUtc, isFalse);
    });

    test('初始化 unknown 项被忽略', () {
      final WaterUsageRecord? record = WaterUsageRecord.fromHistoryItem(
        <String, dynamic>{
          's': 'unknown',
          'a': <String, dynamic>{'event_type': null},
        },
      );
      expect(record, isNull);
    });
  });
}

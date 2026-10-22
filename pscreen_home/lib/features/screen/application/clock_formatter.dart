import 'package:pscreen_screen/features/time/domain/lunar_calendar.dart';

/// 星期中文名（索引 0 = 周一）。
const List<String> kWeekdayCn = <String>[
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// 时钟主显示：`HH:mm:ss`（或 `HH:mm`）。
String formatClockTime(DateTime now, {bool withSeconds = true}) {
  final String base = '${_two(now.hour)}:${_two(now.minute)}';
  return withSeconds ? '$base:${_two(now.second)}' : base;
}

/// 日期行：`2026年10月21日 星期三`。
String formatClockDate(DateTime now) {
  final int weekday = now.weekday - 1;
  return '${now.year}年${now.month}月${now.day}日 星期${kWeekdayCn[weekday]}';
}

/// 农历行：`八月十四`；超出农历表覆盖范围（1900–2099）时返回空串。
String formatLunarLine(DateTime now) {
  final LunarDate? lunar = lunarDateOf(now);
  if (lunar == null) return '';
  return lunar.fullCnString;
}

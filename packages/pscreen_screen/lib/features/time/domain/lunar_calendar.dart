/// 农历换算（纯 Dart，零依赖）。
///
/// 数据覆盖 1900–2099 年，采用每位 16bit 编码：
/// - bit16~13：该年闰哪个月（0 表示无闰月）
/// - bit12：闰月日数（1 → 30，0 → 29）
/// - bit11~0：农历 1~12 月份日数（1 → 30，0 → 29）
/// 以 1900-01-31（农历 1900 正月初一）为基准日。
library;

/// 农历日期（公历换算结果）。
class LunarDate {
  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeap,
  });

  /// 农历年
  final int year;

  /// 农历月（1~12）
  final int month;

  /// 农历日（1~30）
  final int day;

  /// 是否为闰月
  final bool isLeap;

  /// 中文月份名，如「八月」「闰八月」
  String get monthName =>
      '${isLeap ? '闰' : ''}${kLunarMonthCn[month - 1]}月';

  /// 中文日名，如「十四」「初一」
  String get dayName => lunarDayCn(day);

  /// 完整农历日期串，如「八月十四」
  String get fullCnString => '$monthName$dayName';
}

/// 农历月份中文名（下标 0 对应正月）。
const List<String> kLunarMonthCn = <String>[
  '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊',
];

const List<String> _cnDigit = <String>[
  '', '一', '二', '三', '四', '五', '六', '七', '八', '九',
];

/// 农历日中文字符串（1~30）。
String lunarDayCn(int day) {
  if (day == 10) return '初十';
  if (day < 10) return '初${_cnDigit[day]}';
  if (day < 20) return '十${_cnDigit[day - 10]}';
  if (day == 20) return '二十';
  if (day < 30) return '廿${_cnDigit[day - 20]}';
  return '三十';
}

/// 1900–2099 年农历信息表（下标 `year - 1900`）。
/// 数据源自公开的农历信息编码（1901 起沿用通用编码，1900 为无闰 355 天年份）。
const List<int> _lunarData = <int>[
  0x04bd8, // 1900
  0x00752, 0x00ea5, 0x0ab2a, 0x0064b, 0x00a9b, 0x09aa6, 0x0056a, 0x00b59,
  0x04baa, 0x00752, // 1901 ~ 1910
  0x0cda5, 0x00b25, 0x00a4b, 0x0ba4b, 0x002ad, 0x0056b, 0x045b5, 0x00da9,
  0x0fe92, 0x00e92, // 1911 ~ 1920
  0x00d25, 0x0ad2d, 0x00a56, 0x002b6, 0x09ad5, 0x006d4, 0x00ea9, 0x04f4a,
  0x00e92, 0x0c6a6, // 1921 ~ 1930
  0x0052b, 0x00a57, 0x0b956, 0x00b5a, 0x006d4, 0x07761, 0x00749, 0x0fb13,
  0x00a93, 0x0052b, // 1931 ~ 1940
  0x0d51b, 0x00aad, 0x0056a, 0x09da5, 0x00ba4, 0x00b49, 0x04d4b, 0x00a95,
  0x0eaad, 0x00536, // 1941 ~ 1950
  0x00aad, 0x0baca, 0x005b2, 0x00da5, 0x07ea2, 0x00d4a, 0x10595, 0x00a97,
  0x00556, 0x0c575, // 1951 ~ 1960
  0x00ad5, 0x006d2, 0x08755, 0x00ea5, 0x0064a, 0x0664f, 0x00a9b, 0x0eada,
  0x0056a, 0x00b69, // 1961 ~ 1970
  0x0abb2, 0x00b52, 0x00b25, 0x08b2b, 0x00a4b, 0x10aab, 0x002ad, 0x0056d,
  0x0d5a9, 0x00da9, // 1971 ~ 1980
  0x00d92, 0x08e95, 0x00d25, 0x14e4d, 0x00a56, 0x002b6, 0x0c2f5, 0x006d5,
  0x00ea9, 0x0af52, // 1981 ~ 1990
  0x00e92, 0x00d26, 0x0652e, 0x00a57, 0x10ad6, 0x0035a, 0x006d5, 0x0ab69,
  0x00749, 0x00693, // 1991 ~ 2000
  0x08a9b, 0x0052b, 0x00a5b, 0x04aae, 0x0056a, 0x0edd5, 0x00ba4, 0x00b49,
  0x0ad53, 0x00a95, // 2001 ~ 2010
  0x0052d, 0x0855d, 0x00ab5, 0x12baa, 0x005d2, 0x00da5, 0x0de8a, 0x00d4a,
  0x00c95, 0x08a9e, // 2011 ~ 2020
  0x00556, 0x00ab5, 0x04ada, 0x006d2, 0x0c765, 0x00725, 0x0064b, 0x0a657,
  0x00cab, 0x0055a, // 2021 ~ 2030
  0x0656e, 0x00b69, 0x16f52, 0x00b52, 0x00b25, 0x0dd0b, 0x00a4b, 0x004ab,
  0x0a2bb, 0x005ad, // 2031 ~ 2040
  0x00b6a, 0x04daa, 0x00d92, 0x0eea5, 0x00d25, 0x00a55, 0x0ba4d, 0x004b6,
  0x005b5, 0x076d2, // 2041 ~ 2050
  0x00ec9, 0x10f92, 0x00e92, 0x00d26, 0x0d516, 0x00a57, 0x00556, 0x09365,
  0x00755, 0x00749, // 2051 ~ 2060
  0x0674b, 0x00693, 0x0eaab, 0x0052b, 0x00a5b, 0x0aaba, 0x0056a, 0x00b65,
  0x08baa, 0x00b4a, // 2061 ~ 2070
  0x10d95, 0x00a95, 0x0052d, 0x0c56d, 0x00ab5, 0x005aa, 0x085d5, 0x00da5,
  0x00d4a, 0x06e4d, // 2071 ~ 2080
  0x00c96, 0x0ecce, 0x00556, 0x00ab5, 0x0bad2, 0x006d2, 0x00ea5, 0x0872a,
  0x0068b, 0x10697, // 2081 ~ 2090
  0x004ab, 0x0055b, 0x0d556, 0x00b6a, 0x00752, 0x08b95, 0x00b45, 0x00a8b,
  0x04a4f, // 2091 ~ 2099
];

/// 基准日：1900-01-31 为农历 1900 正月初一。
final DateTime _baseDate = DateTime(1900, 1, 31);

int _leapMonth(int year) => (_lunarData[year - 1900] >> 13) & 0xf;

int _leapDays(int year) {
  final int leap = _leapMonth(year);
  if (leap == 0) return 0;
  return ((_lunarData[year - 1900] >> 12) & 1) == 1 ? 30 : 29;
}

int _monthDays(int year, int month) {
  return ((_lunarData[year - 1900] >> (month - 1)) & 1) == 1 ? 30 : 29;
}

int _yearDays(int year) {
  int total = 0;
  for (int m = 1; m <= 12; m++) {
    total += _monthDays(year, m);
  }
  total += _leapDays(year);
  return total;
}

/// 把公历日期换算为农历。范围 1900-01-31 ~ 2099-12-31。
/// 超出范围返回 null。
LunarDate? lunarDateOf(DateTime date) {
  if (date.isBefore(_baseDate)) return null;
  int offset = date.difference(_baseDate).inDays;

  // 定位农历年
  int lunarYear = 1900;
  while (lunarYear < 2100) {
    final int days = _yearDays(lunarYear);
    if (offset < days) break;
    offset -= days;
    lunarYear++;
  }
  if (lunarYear >= 2100) return null;

  // 定位农历月（含闰月，闰月紧随同号月之后，月号与其相同）
  final int leap = _leapMonth(lunarYear);
  int lunarMonth = 1;
  bool isLeapMonth = false;
  for (int m = 1; m <= 12; m++) {
    if (offset < _monthDays(lunarYear, m)) {
      lunarMonth = m;
      isLeapMonth = false;
      break;
    }
    offset -= _monthDays(lunarYear, m);
    if (leap == m) {
      final int leapDays = _leapDays(lunarYear);
      if (offset < leapDays) {
        lunarMonth = m;
        isLeapMonth = true;
        break;
      }
      offset -= leapDays;
    }
  }

  return LunarDate(
    year: lunarYear,
    month: lunarMonth,
    day: offset + 1,
    isLeap: isLeapMonth,
  );
}
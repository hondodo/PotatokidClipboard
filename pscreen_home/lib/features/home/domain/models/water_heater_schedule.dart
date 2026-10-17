/// 定时预热的重复类型。
///
/// 设备实际只同步 `0`（仅一次）/ `1`（每天）；`everyday` 是 HA 实体名示例
/// 里的兼容写法，解析时一并接受。其余类型是米家云端专有，HA 不做。
enum PreheatRepeat {
  once('0', '仅一次'),
  daily('1', '每天');

  const PreheatRepeat(this.token, this.label);

  final String token;
  final String label;

  static PreheatRepeat fromToken(String token) =>
      token == '1' || token == 'everyday' || token == 'daily'
          ? daily
          : once;
}

/// 一个定时预热时段（HA 里是 `text.*_preheat_timer` 的一个槽位）。
class PreheatSlot {
  const PreheatSlot({
    required this.repeat,
    required this.startMinutes,
    required this.endMinutes,
    required this.enabled,
    required this.id,
  });

  /// 空槽位
  factory PreheatSlot.empty(int id) => PreheatSlot(
        repeat: PreheatRepeat.once,
        startMinutes: 0,
        endMinutes: 0,
        enabled: false,
        id: id,
      );

  final PreheatRepeat repeat;

  /// 开始时间（0-1439 分钟）
  final int startMinutes;

  /// 结束时间（0-1439 分钟）
  final int endMinutes;
  final bool enabled;

  /// 设备槽位 id（0-4 或空槽 9）
  final int id;

  bool get isEmpty => startMinutes == 0 && endMinutes == 0;

  String get label =>
      '${_clock(startMinutes)}–${_clock(endMinutes)} · ${repeat.label}';

  PreheatSlot copyWith({
    PreheatRepeat? repeat,
    int? startMinutes,
    int? endMinutes,
    bool? enabled,
    int? id,
  }) =>
      PreheatSlot(
        repeat: repeat ?? this.repeat,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        enabled: enabled ?? this.enabled,
        id: id ?? this.id,
      );

  String encode() =>
      '${repeat.token}&${_hhmm(startMinutes)}&${_hhmm(endMinutes)}'
      '&${enabled ? 1 : 0}&$id';

  static String _hhmm(int minutes) {
    final int hour = (minutes ~/ 60) % 24;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}'
        '${minute.toString().padLeft(2, '0')}';
  }

  static String _clock(int minutes) {
    final int hour = (minutes ~/ 60) % 24;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}

/// 5 个时段的定时预热表。
class PreheatSchedule {
  const PreheatSchedule(this.slots);

  /// 解析 `type&start&end&switch&id-...` 格式；非法/缺省槽位补空。
  factory PreheatSchedule.parse(String? raw) {
    final List<PreheatSlot> slots = <PreheatSlot>[];
    final List<String> parts =
        (raw ?? '').split('-').where((String p) => p.isNotEmpty).toList();
    for (int i = 0; i < 5; i++) {
      if (i >= parts.length) {
        slots.add(PreheatSlot.empty(9));
        continue;
      }
      final List<String> fields = parts[i].split('&');
      if (fields.length < 5) {
        slots.add(PreheatSlot.empty(9));
        continue;
      }
      slots.add(PreheatSlot(
        repeat: PreheatRepeat.fromToken(fields[0]),
        startMinutes: _minutes(fields[1]),
        endMinutes: _minutes(fields[2]),
        enabled: fields[3] == '1' || fields[3] == 'true',
        id: int.tryParse(fields[4]) ?? 9,
      ));
    }
    return PreheatSchedule(slots);
  }

  final List<PreheatSlot> slots;

  String encode() =>
      slots.map((PreheatSlot slot) => slot.encode()).join('-');

  PreheatSchedule replace(int index, PreheatSlot slot) {
    final List<PreheatSlot> next = List<PreheatSlot>.of(slots);
    next[index] = slot;
    return PreheatSchedule(next);
  }

  /// 是否有可执行的时段
  bool get hasEnabled =>
      slots.any((PreheatSlot slot) => slot.enabled && !slot.isEmpty);

  static int _minutes(String raw) {
    final int? value = int.tryParse(raw);
    if (value == null || raw.length < 3) return 0;
    final int hour = value ~/ 100;
    final int minute = value % 100;
    if (hour > 23 || minute > 59) return 0;
    return hour * 60 + minute;
  }
}

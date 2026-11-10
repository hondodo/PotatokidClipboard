import 'package:flutter/foundation.dart';

/// 禁看时段（`quietHours` 条目，支持跨午夜，如 `22:00-06:00`）。
@immutable
class QuietHour {
  const QuietHour({required this.startMinute, required this.endMinute});

  /// 起始分钟（0~1439，自当日 00:00 起）。
  final int startMinute;

  /// 结束分钟（0~1439）；等于起始视为无效（全天禁）。
  final int endMinute;

  /// 解析 `HH:MM-HH:MM`；格式非法返回 null（坏条目直接忽略，不抛错）。
  static QuietHour? tryParse(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    final int dash = text.indexOf('-');
    if (dash <= 0 || dash >= text.length - 1) return null;
    final int? start = _parseHm(text.substring(0, dash));
    final int? end = _parseHm(text.substring(dash + 1));
    if (start == null || end == null) return null;
    if (start == end) return null;
    return QuietHour(startMinute: start, endMinute: end);
  }

  static int? _parseHm(String raw) {
    final String text = raw.trim();
    final int colon = text.indexOf(':');
    if (colon <= 0 || colon >= text.length - 1) return null;
    final int? hour = int.tryParse(text.substring(0, colon).trim());
    final int? minute = int.tryParse(text.substring(colon + 1).trim());
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// [minuteOfDay]（0~1439）是否落在禁看时段内；跨午夜（start > end）取并集。
  bool contains(int minuteOfDay) {
    if (startMinute < endMinute) {
      return minuteOfDay >= startMinute && minuteOfDay < endMinute;
    }
    // 跨午夜：22:00-06:00 → >=22:00 或 <06:00。
    return minuteOfDay >= startMinute || minuteOfDay < endMinute;
  }

  /// 序列化为 `HH:MM-HH:MM`（与 [tryParse] 互逆）。
  String format() => '${_fmt(startMinute)}-${_fmt(endMinute)}';

  @override
  String toString() => format();

  static String _fmt(int minute) {
    final String h = (minute ~/ 60).toString().padLeft(2, '0');
    final String m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 一个孩子的观看规则档案（`children[]` 元素）。
@immutable
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    this.age,
    this.profileMode = 'mild',
    this.locked = false,
    this.avatar,
    this.hideGroups = const <String>[],
    this.hideChannels = const <String>[],
    this.allowGroups = const <String>[],
    this.allowChannels = const <String>[],
    this.sessionLimitMin = 0,
    this.dailyLimitMin = 0,
    this.quietHours = const <QuietHour>[],
  });

  final String id;
  final String name;
  final int? age;

  /// 档位：`mild`（减法：黑名单）/ `strict`（加法：白名单）。
  final String profileMode;

  /// 是否受验证保护（勾选该档案需家长验证）。
  final bool locked;

  /// 头像；可选。
  ///
  /// - `null` / 空 → 客户端回落（preset 或按 id 派生）
  /// - `preset:avatar001` 等 → 内置资源（`packages/pscreen_screen/assets/parental/avatars/avatar001.png`）
  /// - `http(s)://` 开头 → 家长上传到 app_server 的公网直链
  final String? avatar;

  /// 温和档：分组黑名单 / 频道名黑名单（两者取并集隐藏）。
  final List<String> hideGroups;
  final List<String> hideChannels;

  /// 严格档：分组白名单 / 频道名白名单（两字段取交集）。
  final List<String> allowGroups;
  final List<String> allowChannels;

  /// 单次连续观看限额（分钟）；0/缺失 = 该维度不启用。
  final int sessionLimitMin;

  /// 单日累计限额（分钟）；0/缺失 = 该维度不启用。
  final int dailyLimitMin;

  /// 禁看时段（该档案；多孩选中时取并集）。
  final List<QuietHour> quietHours;

  bool get isStrict => profileMode == 'strict';

  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String name = (json['name'] as String?)?.trim() ?? '';
    final String? avatar = (() {
      final raw = json['avatar'];
      if (raw is String) {
        final String s = raw.trim();
        if (s.isEmpty) return null;
        // 宽松解析：preset:xxx 或以 http(s):// 开头都接受；非法值回落 null。
        if (s.startsWith('preset:')) return s;
        if (s.startsWith('http://') || s.startsWith('https://')) return s;
      }
      return null;
    })();
    return ChildProfile(
      id: id,
      name: name.isEmpty ? id : name,
      age: json['age'] is num ? (json['age'] as num).toInt() : null,
      profileMode: json['profileMode'] == 'strict' ? 'strict' : 'mild',
      locked: json['locked'] == true,
      avatar: avatar,
      hideGroups: _stringList(json['hideGroups']),
      hideChannels: _stringList(json['hideChannels']),
      allowGroups: _stringList(json['allowGroups']),
      allowChannels: _stringList(json['allowChannels']),
      sessionLimitMin: _nonNegInt(json['sessionLimitMin']),
      dailyLimitMin: _nonNegInt(json['dailyLimitMin']),
      quietHours: _quietHours(json['quietHours']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (age != null) 'age': age,
        'profileMode': profileMode,
        if (locked) 'locked': true,
        if (avatar != null && avatar!.isNotEmpty) 'avatar': avatar,
        if (hideGroups.isNotEmpty) 'hideGroups': hideGroups,
        if (hideChannels.isNotEmpty) 'hideChannels': hideChannels,
        if (allowGroups.isNotEmpty) 'allowGroups': allowGroups,
        if (allowChannels.isNotEmpty) 'allowChannels': allowChannels,
        if (sessionLimitMin > 0) 'sessionLimitMin': sessionLimitMin,
        if (dailyLimitMin > 0) 'dailyLimitMin': dailyLimitMin,
        if (quietHours.isNotEmpty)
          'quietHours': quietHours.map((QuietHour q) => q.toString()).toList(),
      };

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static int _nonNegInt(Object? raw) {
    if (raw is! num) return 0;
    final int v = raw.toInt();
    return v < 0 ? 0 : v;
  }

  static List<QuietHour> _quietHours(Object? raw) {
    if (raw is! List) return const <QuietHour>[];
    final List<QuietHour> out = <QuietHour>[];
    for (final Object? item in raw) {
      if (item is String) {
        final QuietHour? q = QuietHour.tryParse(item);
        if (q != null) out.add(q);
      }
    }
    return out;
  }
}

/// 儿童模式配置（服务端 `config` 帧的 `parental` 字段 / 本地临时配置同构）。
@immutable
class ParentalConfig {
  const ParentalConfig({
    this.mode = 'off',
    this.activeChildIds = const <String>[],
    this.children = const <ChildProfile>[],
    this.unlockMode = 'remote',
    this.pin = '',
    this.ownerAccount = '',
  });

  /// 全局总开关：`off | on`（`off` = 整层关闭、全部字段忽略）。
  final String mode;

  /// 当前观看的孩子（可多位）；电视端持久化，重启保持为默认预选。
  final List<String> activeChildIds;

  /// 儿童档案列表。
  final List<ChildProfile> children;

  /// 解锁方式：`remote | pin | arith | quiz`（quiz = 家长题库答题解锁）。
  final String unlockMode;

  /// PIN（明文下发，家庭场景 v1 接受）。
  final String pin;

  /// 该 TV 的家长账号（`parent` 角色）；缺省回退 `machine.owner` → `1000001`。
  final String ownerAccount;

  /// **生效判定式（全文统一）**：`mode === 'on' && children` 非空。
  ///
  /// 不用「≠ off」——老配置无 parental 字段时 `mode` 为 `undefined`，
  /// `undefined !== 'off'` 为 true 会误判；统一正向判定，缺省即未启用。
  bool get enabled => mode == 'on' && children.isNotEmpty;

  /// 按 id 查档案。
  ChildProfile? childById(String id) {
    for (final ChildProfile c in children) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 过滤 `activeChildIds` 中已不在 `children` 里的 id（家长删档案后的悬空引用）。
  ///
  /// 部分悬空 → 过滤后返回剩余 id；全部悬空 → 返回空列表（视为未选）。
  List<String> resolveActiveChildIds(Iterable<String>? ids) {
    if (ids == null) return const <String>[];
    final List<String> out = <String>[];
    for (final String id in ids) {
      if (childById(id) != null && !out.contains(id)) out.add(id);
    }
    return out;
  }

  /// 选中档案列表（按 `ids` 顺序，已过滤悬空）。
  List<ChildProfile> profilesOf(Iterable<String>? ids) {
    final List<ChildProfile> out = <ChildProfile>[];
    for (final String id in resolveActiveChildIds(ids)) {
      final ChildProfile? c = childById(id);
      if (c != null) out.add(c);
    }
    return out;
  }

  /// 多孩选中时的 `quietHours` **并集**（任一档案命中即禁）。
  List<QuietHour> quietHoursUnion(Iterable<String>? ids) {
    final List<QuietHour> out = <QuietHour>[];
    for (final ChildProfile c in profilesOf(ids)) {
      out.addAll(c.quietHours);
    }
    return out;
  }

  factory ParentalConfig.fromJson(Map<String, dynamic> json) {
    final List<ChildProfile> children = <ChildProfile>[];
    final Object? rawChildren = json['children'];
    if (rawChildren is List) {
      for (final Object? item in rawChildren) {
        if (item is Map<String, dynamic>) {
          final ChildProfile c = ChildProfile.fromJson(item);
          if (c.id.isNotEmpty) children.add(c);
        } else if (item is Map) {
          final ChildProfile c =
              ChildProfile.fromJson(Map<String, dynamic>.from(item));
          if (c.id.isNotEmpty) children.add(c);
        }
      }
    }
    return ParentalConfig(
      mode: json['mode'] == 'on' ? 'on' : 'off',
      activeChildIds: _stringList(json['activeChildIds']),
      children: children,
      unlockMode: json['unlockMode'] == 'pin'
          ? 'pin'
          : json['unlockMode'] == 'arith'
              ? 'arith'
              : json['unlockMode'] == 'quiz'
                  ? 'quiz'
                  : 'remote',
      pin: (json['pin'] as String?) ?? '',
      ownerAccount: (json['ownerAccount'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode,
        if (activeChildIds.isNotEmpty) 'activeChildIds': activeChildIds,
        'children': children.map((ChildProfile c) => c.toJson()).toList(),
        'unlockMode': unlockMode,
        if (pin.isNotEmpty) 'pin': pin,
        if (ownerAccount.isNotEmpty) 'ownerAccount': ownerAccount,
      };

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }
}

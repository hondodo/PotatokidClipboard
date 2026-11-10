/// 儿童模式管控配置：服务端设备 config 帧的 `parental` 字段（方案 2.2）。
///
/// 结构与服务端约定同构：`mode` 是全局总开关（`on` 才整层生效），
/// 观看规则全部下沉到 [children] 每个儿童档案（按档案 `profileMode`
/// 分 mild/strict 两档），`unlockMode` / `pin` / `ownerAccount` 是
/// 远程解锁链路参数。服务端 parental 存储由服务端任务落地，本类只保证
/// 手机端与服务端的序列化一致。
class ParentalConfig {
  const ParentalConfig({
    this.mode = 'off',
    this.activeChildIds = const <String>[],
    this.children = const <ParentalChild>[],
    this.unlockMode = 'remote',
    this.pin = '',
    this.ownerAccount = '',
  });

  /// 全局总开关：`off | on`（`off` = 整层关闭、全部字段忽略）。
  final String mode;

  /// 当前观看的孩子（电视端最新上报的选人结果）。
  final List<String> activeChildIds;

  /// 多儿童档案（观看规则 / 限额 / 时段按档案生效）。
  final List<ParentalChild> children;

  /// 解锁方式：`remote`（远程确认）/ `pin`（PIN 兜底）/ `arith`（算术题兜底）。
  final String unlockMode;

  /// 4 位解锁 PIN（`unlockMode == 'pin'` 时使用）。
  final String pin;

  /// 该 TV 的家长账号；空串时回落 `machine.owner`（方案 4.2 统一判定）。
  final String ownerAccount;

  static const ParentalConfig empty = ParentalConfig();

  /// 生效判定（全文统一）：`mode == 'on' && children 非空`。
  /// 不用「≠ off」——老配置无 parental 字段时 `mode` 缺省即未启用。
  bool get enabled => mode == 'on' && children.isNotEmpty;

  factory ParentalConfig.fromJson(Map<String, dynamic> json) {
    final dynamic rawChildren = json['children'];
    return ParentalConfig(
      mode: _string(json['mode'], fallback: 'off'),
      activeChildIds: _stringList(json['activeChildIds']),
      children: rawChildren is List
          ? rawChildren
                .whereType<Map>()
                .map((Map item) =>
                    ParentalChild.fromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false)
          : const <ParentalChild>[],
      unlockMode: _string(json['unlockMode'], fallback: 'remote'),
      pin: _string(json['pin']),
      ownerAccount: _string(json['ownerAccount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode,
        'activeChildIds': activeChildIds,
        'children': children
            .map((ParentalChild child) => child.toJson())
            .toList(growable: false),
        'unlockMode': unlockMode,
        'pin': pin,
        'ownerAccount': ownerAccount,
      };

  ParentalConfig copyWith({
    String? mode,
    List<String>? activeChildIds,
    List<ParentalChild>? children,
    String? unlockMode,
    String? pin,
    String? ownerAccount,
  }) =>
      ParentalConfig(
        mode: mode ?? this.mode,
        activeChildIds: activeChildIds ?? this.activeChildIds,
        children: children ?? this.children,
        unlockMode: unlockMode ?? this.unlockMode,
        pin: pin ?? this.pin,
        ownerAccount: ownerAccount ?? this.ownerAccount,
      );
}

/// 单个儿童档案：名称 / 年龄 / 档位 / 可见性规则 / 限额 / 时段 / 锁定标记。
///
/// 按档位两套可见性字段（方案 2.2 两档语义）：
/// - `mild` 减法档：`hideGroups` + `hideChannels` 黑名单；
/// - `strict` 加法档：`allowGroups` + `allowChannels` 白名单。
class ParentalChild {
  const ParentalChild({
    required this.id,
    required this.name,
    this.age,
    this.profileMode = 'mild',
    this.avatar,
    this.hideGroups = const <String>[],
    this.hideChannels = const <String>[],
    this.allowGroups = const <String>[],
    this.allowChannels = const <String>[],
    this.sessionLimitMin,
    this.dailyLimitMin,
    this.quietHours = const <String>[],
    this.locked = false,
  });

  final String id;
  final String name;
  final int? age;

  /// 档位：`mild | strict`（唯一按档案生效的档位来源）。
  final String profileMode;

  /// 头像；可选。`preset:xxx` / `http(s)://...`；空 = 客户端回落。
  final String? avatar;

  final List<String> hideGroups;
  final List<String> hideChannels;
  final List<String> allowGroups;
  final List<String> allowChannels;

  /// 单次连续观看限额（分钟）；null/0 = 不启用。
  final int? sessionLimitMin;

  /// 单日累计限额（分钟）；null/0 = 不启用。
  final int? dailyLimitMin;

  /// 禁看时段（如 `22:00-06:00`，支持跨午夜）。
  final List<String> quietHours;

  /// 是否受验证保护（选人页 `locked` 闸门）。
  final bool locked;

  bool get isStrict => profileMode == 'strict';

  /// 档位标签（UI 展示用）。
  String get profileModeLabel => isStrict ? '严格档' : '温和档';

  factory ParentalChild.fromJson(Map<String, dynamic> json) {
    final String? avatar = (() {
      final dynamic raw = json['avatar'];
      if (raw is String) {
        final String s = raw.trim();
        if (s.isEmpty) return null;
        if (s.startsWith('preset:')) return s;
        if (s.startsWith('http://') || s.startsWith('https://')) return s;
      }
      return null;
    })();
    return ParentalChild(
      id: _string(json['id']),
      name: _string(json['name']),
      age: _int(json['age']),
      profileMode: _string(json['profileMode'], fallback: 'mild') == 'strict'
          ? 'strict'
          : 'mild',
      avatar: avatar,
      hideGroups: _stringList(json['hideGroups']),
      hideChannels: _stringList(json['hideChannels']),
      allowGroups: _stringList(json['allowGroups']),
      allowChannels: _stringList(json['allowChannels']),
      sessionLimitMin: _int(json['sessionLimitMin']),
      dailyLimitMin: _int(json['dailyLimitMin']),
      quietHours: _stringList(json['quietHours']),
      locked: json['locked'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (age != null) 'age': age,
        'profileMode': profileMode,
        if (avatar != null && avatar!.isNotEmpty) 'avatar': avatar,
        'hideGroups': hideGroups,
        'hideChannels': hideChannels,
        'allowGroups': allowGroups,
        'allowChannels': allowChannels,
        if (sessionLimitMin != null) 'sessionLimitMin': sessionLimitMin,
        if (dailyLimitMin != null) 'dailyLimitMin': dailyLimitMin,
        'quietHours': quietHours,
        'locked': locked,
      };

  ParentalChild copyWith({
    String? name,
    int? age,
    String? profileMode,
    String? avatar,
    List<String>? hideGroups,
    List<String>? hideChannels,
    List<String>? allowGroups,
    List<String>? allowChannels,
    int? sessionLimitMin,
    int? dailyLimitMin,
    List<String>? quietHours,
    bool? locked,
  }) =>
      ParentalChild(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        profileMode: profileMode ?? this.profileMode,
        avatar: avatar ?? this.avatar,
        hideGroups: hideGroups ?? this.hideGroups,
        hideChannels: hideChannels ?? this.hideChannels,
        allowGroups: allowGroups ?? this.allowGroups,
        allowChannels: allowChannels ?? this.allowChannels,
        sessionLimitMin: sessionLimitMin ?? this.sessionLimitMin,
        dailyLimitMin: dailyLimitMin ?? this.dailyLimitMin,
        quietHours: quietHours ?? this.quietHours,
        locked: locked ?? this.locked,
      );
}

String _string(dynamic value, {String fallback = ''}) {
  final String text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final String text = '${value ?? ''}'.trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
        .map((dynamic item) => '${item ?? ''}'.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
}

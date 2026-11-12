/// 儿童模式管控配置：服务端设备 config 帧的 `parental` 字段（方案 2.2）。
///
/// 结构与服务端约定同构：`mode` 是全局总开关（`on` 才整层生效），
/// 观看规则全部下沉到 [children] 每个儿童档案（按档案 `profileMode`
/// 分 mild/strict 两档），`unlockMode` / `pin` / `ownerAccount` 是
/// 远程解锁链路参数。档案引用共享用两层字段表达：
/// - [ParentalChild.sharedTo]：本台主本档案允许哪些家长号引用（owner opt-in）；
/// - [shared]：本台从别处引用进来的档案坐标，绝不存副本。
///
/// 服务端 parental 存储由服务端任务落地，本类只保证手机端与服务端的序列化一致。
class ParentalConfig {
  const ParentalConfig({
    this.mode = 'off',
    this.activeChildIds = const <String>[],
    this.children = const <ParentalChild>[],
    this.shared = const <ParentalSharedRef>[],
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

  /// 本台「引用进来」的档案坐标（主本仍在别的电视 / 家长名下）。
  ///
  /// 服务端只存 `{refId, owner, machineId, childId, createdAt}`，读取时再展开
  /// 主本内容；来源被删/解绑/取消分享时由服务端标 broken，客户端不静默丢弃。
  final List<ParentalSharedRef> shared;

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
    final dynamic rawShared = json['shared'];
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
      shared: rawShared is List
          ? rawShared
                .whereType<Map>()
                .map((Map item) =>
                    ParentalSharedRef.fromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false)
          : const <ParentalSharedRef>[],
      unlockMode: _string(json['unlockMode'], fallback: 'remote'),
      pin: _string(json['pin']),
      ownerAccount: _string(json['ownerAccount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode,
        'activeChildIds': activeChildIds,
        // readOnly 是展示层为「今天」页临时展开的引用档案，绝不写回主本列表；
        // 否则一次暂停/加时保存就能把别人的档案复制成本台主本。
        'children': children
            .where((ParentalChild child) => !child.readOnly)
            .map((ParentalChild child) => child.toJson())
            .toList(growable: false),
        // 引用坐标必须随整份配置回写：否则在规则页改档案会清空已引用列表。
        'shared': shared
            .map((ParentalSharedRef ref) => ref.toJson())
            .toList(growable: false),
        'unlockMode': unlockMode,
        'pin': pin,
        'ownerAccount': ownerAccount,
      };

  ParentalConfig copyWith({
    String? mode,
    List<String>? activeChildIds,
    List<ParentalChild>? children,
    List<ParentalSharedRef>? shared,
    String? unlockMode,
    String? pin,
    String? ownerAccount,
  }) =>
      ParentalConfig(
        mode: mode ?? this.mode,
        activeChildIds: activeChildIds ?? this.activeChildIds,
        children: children ?? this.children,
        shared: shared ?? this.shared,
        unlockMode: unlockMode ?? this.unlockMode,
        pin: pin ?? this.pin,
        ownerAccount: ownerAccount ?? this.ownerAccount,
      );
}

/// 一条档案引用坐标：只记录“指向谁”，不含档案内容副本。
///
/// 内容实时回源电视的主本档案读取，所以主本改一次、所有引用方自动同步。
/// `refId` 形如 `<来源机器id>:<来源档案id>`，同时用于取消引用。
class ParentalSharedRef {
  const ParentalSharedRef({
    required this.refId,
    required this.owner,
    required this.machineId,
    required this.childId,
    this.createdAtMs = 0,
  });

  final String refId;

  /// 来源档案的主本家长号（判断来源是否仍绑定/是否被移出分享名单）。
  final String owner;
  final String machineId;
  final String childId;
  final int createdAtMs;

  factory ParentalSharedRef.fromJson(Map<String, dynamic> json) {
    final String machineId = _string(json['machineId']);
    final String childId = _string(json['childId']);
    return ParentalSharedRef(
      refId: _string(json['refId'],
          fallback: machineId.isEmpty || childId.isEmpty
              ? ''
              : '$machineId:$childId'),
      owner: _string(json['owner']),
      machineId: machineId,
      childId: childId,
      createdAtMs: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'refId': refId,
        'owner': owner,
        'machineId': machineId,
        'childId': childId,
        'createdAt': createdAtMs,
      };
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
    this.sharedTo = const <String>[],
    this.readOnly = false,
    this.sourceLabel,
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

  /// 跨家长分享白名单：只有名单里的家长号能看到并引用这份主本档案。
  ///
  /// 留空＝不分享；同家长号名下的其它电视默认可见，不依赖这个字段。
  final List<String> sharedTo;

  /// 仅供展示的「引用档案」标记：true 时暂停/加时/改规则入口全部隐藏。
  ///
  /// 这是客户端展示态，不写回服务端；[toJson] 会过滤掉这些档案，避免把
  /// 引用副本误存成本台 `children[]` 主本。
  final bool readOnly;

  /// 引用档案的来源展示（如「妈妈 · 卧室电视」），仅 readOnly 时有值。
  final String? sourceLabel;

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
      sharedTo: _stringList(json['sharedTo']),
      readOnly: json['readOnly'] == true,
      sourceLabel:
          json['sourceLabel'] == null ? null : _string(json['sourceLabel']),
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
        'sharedTo': sharedTo,
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
    List<String>? sharedTo,
    bool? readOnly,
    String? sourceLabel,
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
        sharedTo: sharedTo ?? this.sharedTo,
        readOnly: readOnly ?? this.readOnly,
        sourceLabel: sourceLabel ?? this.sourceLabel,
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

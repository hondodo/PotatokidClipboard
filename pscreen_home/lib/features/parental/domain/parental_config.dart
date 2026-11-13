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

/// 家庭档案分配到的某台电视的引用（仅展示用，不含配置）。
class FamilyTvRef {
  const FamilyTvRef({required this.id, required this.name});

  final String id;
  final String name;

  factory FamilyTvRef.fromJson(Map<String, dynamic> json) =>
      FamilyTvRef(id: _string(json['id']), name: _string(json['name']));
}

/// 家庭级儿童主档案（D-02 / Task 32）：按 `childId` 全局唯一，不含 `deviceId`。
///
/// 与服务端 `familyStore.data.children` + `GET /api/admin/parental/children`
/// 的投影同构：配额与限制类规则（限额 / 禁看时段 / 黑白名单 / 档位）全部归这里，
/// 电视端只按分配表投影已启用的档案，不提供逐台改规则的入口（S2）。
///
/// `sharedTo` 在 D-02 + CR-01 后挂到**题库实体**上，这里只回显方便 UI 提示；
/// `assignedTo` 是只读展示字段（哪些电视启用本档案），改分配走 assignment 接口。
class FamilyChild {
  const FamilyChild({
    required this.id,
    required this.name,
    this.age,
    this.avatarId,
    this.profileMode = 'mild',
    this.dailyLimitMin = 0,
    this.sessionLimitMin = 0,
    this.bedtimeStart = '',
    this.bedtimeEnd = '',
    this.blacklist = const <String>[],
    this.whitelist = const <String>[],
    this.locked = false,
    this.sharedTo = const <String>[],
    this.assignedTo = const <FamilyTvRef>[],
    this.revision = 0,
  });

  final String id;
  final String name;
  final int? age;

  /// 头像素材 id（app_server 镜像 sha256）；空 = 客户端回落预设。
  final String? avatarId;

  /// 档位：`mild | strict`（唯一按档案生效的档位来源）。
  final String profileMode;

  /// 单日累计限额（分钟）；0 = 不启用。
  final int dailyLimitMin;

  /// 单次连续观看限额（分钟）；0 = 不启用。
  final int sessionLimitMin;

  /// 禁看时段起点（如 `22:00`）；空 = 不启用。
  final String bedtimeStart;

  /// 禁看时段终点（如 `06:00`）；空 = 不启用。
  final String bedtimeEnd;

  /// 温和档黑名单 / 严格档白名单（按 profileMode 解读）。
  final List<String> blacklist;
  final List<String> whitelist;

  /// 是否受验证保护（选人页 locked 闸门）。
  final bool locked;

  /// 题库分享白名单（CR-01：只授权家长号，不传 childId）。
  final List<String> sharedTo;

  /// 只读展示：哪些电视启用了本档案（来自 assignment 反向索引）。
  final List<FamilyTvRef> assignedTo;

  /// D-01：服务端维护的实体版本号（展示态，不写入配置字段；保存时作为 `baseRevision` 回传）。
  final int revision;

  bool get isStrict => profileMode == 'strict';
  String get profileModeLabel => isStrict ? '严格档' : '温和档';

  factory FamilyChild.fromJson(Map<String, dynamic> json) {
    final dynamic rawAssigned = json['assignedTo'];
    final List<FamilyTvRef> assigned = rawAssigned is List
        ? rawAssigned
            .whereType<Map>()
            .map((Map item) =>
                FamilyTvRef.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <FamilyTvRef>[];
    return FamilyChild(
      id: _string(json['id'], fallback: _string(json['childId'])),
      name: _string(json['name']),
      age: _int(json['age']),
      avatarId: _string(json['avatarId'], fallback: _string(json['avatar'])),
      profileMode: _string(json['profileMode'], fallback: 'mild') == 'strict'
          ? 'strict'
          : 'mild',
      dailyLimitMin: _int(json['dailyLimitMin']) ?? 0,
      sessionLimitMin: _int(json['sessionLimitMin']) ?? 0,
      bedtimeStart: _string(json['bedtimeStart']),
      bedtimeEnd: _string(json['bedtimeEnd']),
      blacklist: _stringList(json['blacklist']),
      whitelist: _stringList(json['whitelist']),
      locked: json['locked'] == true,
      sharedTo: _stringList(json['sharedTo']),
      assignedTo: assigned,
      revision: _int(json['revision']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (age != null) 'age': age,
        if (avatarId != null && avatarId!.isNotEmpty) 'avatarId': avatarId,
        'profileMode': profileMode,
        'dailyLimitMin': dailyLimitMin,
        'sessionLimitMin': sessionLimitMin,
        if (bedtimeStart.isNotEmpty) 'bedtimeStart': bedtimeStart,
        if (bedtimeEnd.isNotEmpty) 'bedtimeEnd': bedtimeEnd,
        'blacklist': blacklist,
        'whitelist': whitelist,
        'locked': locked,
      };

  FamilyChild copyWith({
    String? name,
    int? age,
    String? avatarId,
    String? profileMode,
    int? dailyLimitMin,
    int? sessionLimitMin,
    String? bedtimeStart,
    String? bedtimeEnd,
    List<String>? blacklist,
    List<String>? whitelist,
    bool? locked,
    List<String>? sharedTo,
    List<FamilyTvRef>? assignedTo,
  }) =>
      FamilyChild(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        avatarId: avatarId ?? this.avatarId,
        profileMode: profileMode ?? this.profileMode,
        dailyLimitMin: dailyLimitMin ?? this.dailyLimitMin,
        sessionLimitMin: sessionLimitMin ?? this.sessionLimitMin,
        bedtimeStart: bedtimeStart ?? this.bedtimeStart,
        bedtimeEnd: bedtimeEnd ?? this.bedtimeEnd,
        blacklist: blacklist ?? this.blacklist,
        whitelist: whitelist ?? this.whitelist,
        locked: locked ?? this.locked,
        sharedTo: sharedTo ?? this.sharedTo,
        assignedTo: assignedTo ?? this.assignedTo,
        revision: revision,
      );
}

/// CR-01：一份分享给我的题库（他人 `sharedTo` 含我），用于一键复制副本。
///
/// 仅含来源账号 / 来源 childId / 题目数等匿名聚合信息，不含任何观看时长、
/// 观看记录或孩子姓名以外的隐私（Q3 口径）。
class SharedQuizInfo {
  const SharedQuizInfo({
    required this.sourceAccount,
    required this.sourceChildId,
    required this.childName,
    required this.questionCount,
  });

  /// 来源题库所属家长号（作者）。
  final String sourceAccount;

  /// 来源档案的 childId（题库按 childId 分库）。
  final String sourceChildId;

  /// 来源档案的展示名（仅用于选择时辨认，不用于统计）。
  final String childName;

  /// 题目数量（匿名聚合，不含内容预览）。
  final int questionCount;

  factory SharedQuizInfo.fromJson(Map<String, dynamic> json) => SharedQuizInfo(
        sourceAccount: _string(json['sourceAccount']),
        sourceChildId: _string(json['sourceChildId']),
        childName: _string(json['childName']),
        questionCount: _int(json['questionCount']) ?? 0,
      );
}

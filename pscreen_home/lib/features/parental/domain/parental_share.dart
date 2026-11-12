/// 档案引用共享的“展开视图”模型。
///
/// 服务端 `GET /api/admin/parental/shared-view` 与三个写接口都返回同一份结构：
/// - `masters`：本台主本档案（含 `sharedTo` 白名单，可改）；
/// - `imported`：本台引用进来的档案（只读；来源失效时 `status=broken`）；
/// - `candidates`：当前家长可引用的档案（同号跨电视 / 其他家长显式分享给我）。
///
/// 这里只做解析与只读计算，不发起网络请求；写操作由 `ParentalAdminApi` 负责。
class ParentalShareView {
  const ParentalShareView({
    this.masters = const <ParentalShareMaster>[],
    this.imported = const <ParentalShareImported>[],
    this.candidates = const <ParentalShareCandidate>[],
  });

  final List<ParentalShareMaster> masters;
  final List<ParentalShareImported> imported;
  final List<ParentalShareCandidate> candidates;

  static const ParentalShareView empty = ParentalShareView();

  bool get isEmpty => masters.isEmpty && imported.isEmpty && candidates.isEmpty;

  factory ParentalShareView.fromJson(Map<String, dynamic> json) {
    return ParentalShareView(
      masters: _listOf(json['masters'], ParentalShareMaster.fromJson),
      imported: _listOf(json['imported'], ParentalShareImported.fromJson),
      candidates: _listOf(json['candidates'], ParentalShareCandidate.fromJson),
    );
  }

  static List<T> _listOf<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) factory,
  ) {
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((Map item) => factory(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}

/// 本台主本档案：`sharedTo` 是“允许引用我的家长号”白名单，留空＝不分享。
class ParentalShareMaster {
  const ParentalShareMaster({
    required this.id,
    required this.name,
    this.profileMode = 'mild',
    this.dailyLimitMin,
    this.sessionLimitMin,
    this.locked = false,
    this.sharedTo = const <String>[],
    this.isMaster = true,
    this.readOnly = false,
  });

  final String id;
  final String name;
  final String profileMode;
  final int? dailyLimitMin;
  final int? sessionLimitMin;
  final bool locked;
  final List<String> sharedTo;
  final bool isMaster;
  final bool readOnly;

  bool get isStrict => profileMode == 'strict';

  String get profileModeLabel => isStrict ? '严格档' : '温和档';

  factory ParentalShareMaster.fromJson(Map<String, dynamic> json) =>
      ParentalShareMaster(
        id: _shareString(json['id']),
        name: _shareString(json['name']),
        profileMode: _shareString(json['profileMode'], fallback: 'mild'),
        dailyLimitMin: _shareInt(json['dailyLimitMin']),
        sessionLimitMin: _shareInt(json['sessionLimitMin']),
        locked: json['locked'] == true,
        sharedTo: _shareStringList(json['sharedTo']),
        isMaster: json['isMaster'] != false,
        readOnly: json['readOnly'] == true,
      );
}

/// 引用进来的档案：内容来自主本，本台只读。
///
/// `status == 'broken'` 时只保留占位，`name` 可能是服务端给的回退文案；
/// 不允许编辑 / 打开题库写操作，只能取消后重新选择。
class ParentalShareImported {
  const ParentalShareImported({
    required this.refId,
    required this.id,
    required this.name,
    this.profileMode = 'mild',
    this.dailyLimitMin,
    this.sessionLimitMin,
    this.locked = false,
    this.status = 'ok',
    this.reason,
    this.source,
    this.isMaster = false,
    this.readOnly = true,
  });

  final String refId;

  /// 主本档案 id（在本台的配置里用于关联观看上报）。
  final String id;
  final String name;
  final String profileMode;
  final int? dailyLimitMin;
  final int? sessionLimitMin;
  final bool locked;
  final String status;
  final String? reason;
  final ParentalShareSource? source;
  final bool isMaster;
  final bool readOnly;

  bool get isBroken => status == 'broken';

  bool get isStrict => profileMode == 'strict';

  String get profileModeLabel => isStrict ? '严格档' : '温和档';

  String get sourceLabel {
    final ParentalShareSource? s = source;
    if (s == null) return '主本电视';
    final String owner = s.owner.isNotEmpty ? '${s.owner} · ' : '';
    final String tv = s.machineName.isNotEmpty
        ? s.machineName
        : (s.machineId.isNotEmpty ? s.machineId : '主本电视');
    return '$owner$tv';
  }

  factory ParentalShareImported.fromJson(Map<String, dynamic> json) {
    final dynamic rawSource = json['source'];
    return ParentalShareImported(
      refId: _shareString(json['refId']),
      id: _shareString(json['id']),
      name: _shareString(json['name']),
      profileMode: _shareString(json['profileMode'], fallback: 'mild'),
      dailyLimitMin: _shareInt(json['dailyLimitMin']),
      sessionLimitMin: _shareInt(json['sessionLimitMin']),
      locked: json['locked'] == true,
      status: _shareString(json['status'], fallback: 'ok'),
      reason: json['reason'] == null ? null : _shareString(json['reason']),
      source: rawSource is Map
          ? ParentalShareSource.fromJson(Map<String, dynamic>.from(rawSource))
          : null,
      isMaster: json['isMaster'] == true,
      readOnly: json['readOnly'] != false,
    );
  }
}

/// 引用坐标里的来源电视信息（服务端只存坐标，内容实时回主本读取）。
class ParentalShareSource {
  const ParentalShareSource({
    this.machineId = '',
    this.machineName = '',
    this.owner = '',
    this.childId = '',
  });

  final String machineId;
  final String machineName;
  final String owner;
  final String childId;

  factory ParentalShareSource.fromJson(Map<String, dynamic> json) =>
      ParentalShareSource(
        machineId: _shareString(json['machineId']),
        machineName: _shareString(json['machineName']),
        owner: _shareString(json['owner']),
        childId: _shareString(json['childId']),
      );
}

/// 一条可引用候选：`via == 'same-account'` 是同家长号跨电视；
/// `via == 'shared-to-me'` 是其他家长在档案上显式把当前家长号加入了白名单。
class ParentalShareCandidate {
  const ParentalShareCandidate({
    required this.machineId,
    required this.machineName,
    required this.childId,
    required this.name,
    this.owner = '',
    this.profileMode = 'mild',
    this.dailyLimitMin,
    this.via = 'same-account',
    this.isTv = true,
  });

  final String machineId;
  final String machineName;
  final String childId;
  final String name;
  final String owner;
  final String profileMode;
  final int? dailyLimitMin;
  final String via;
  final bool isTv;

  bool get isSameAccount => via == 'same-account';

  String get groupLabel => isSameAccount ? '同一家长号 · 跨电视' : '其他家长分享给我';

  factory ParentalShareCandidate.fromJson(Map<String, dynamic> json) =>
      ParentalShareCandidate(
        machineId: _shareString(json['machineId']),
        machineName: _shareString(json['machineName']),
        childId: _shareString(json['childId']),
        name: _shareString(json['name']),
        owner: _shareString(json['owner']),
        profileMode: _shareString(json['profileMode'], fallback: 'mild'),
        dailyLimitMin: _shareInt(json['dailyLimitMin']),
        via: _shareString(json['via'], fallback: 'same-account'),
        isTv: json['isTv'] != false,
      );
}

/// 服务端 broken 原因→家长能看懂的提示；未知原因也给可操作指引。
String parentalShareReasonLabel(String? reason) {
  switch (reason) {
    case 'machine-missing':
      return '来源电视已不存在 · 保留占位，请重新选择';
    case 'child-missing':
      return '主本档案已删除 · 保留占位，请重新选择';
    case 'owner-unbound':
      return '来源家长已解绑 · 保留占位，请重新选择';
    case 'not-shared-to-viewer':
      return '主本已取消对你的分享 · 保留占位，请重新选择';
    default:
      return '来源已失效 · 保留占位，请重新选择';
  }
}

String _shareString(dynamic value, {String fallback = ''}) {
  final String text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

int? _shareInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final String text = '${value ?? ''}'.trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

List<String> _shareStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((dynamic item) => '${item ?? ''}'.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}

import 'dart:async';
import 'dart:convert';

import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 遥控会话的目标设备：原始账号 + 可选备注名。
///
/// 不再使用 tvs.json 预设：会话列表只显示这里添加过的账号，
/// 通过会话页右上角「+」手动输入或扫码添加。
class ThreadTarget {
  const ThreadTarget({required this.account, this.alias = ''});

  final String account;

  /// 备注名；空串表示未改名（列表显示原始账号）。
  final String alias;

  /// 列表主标题：有备注用备注，否则用原始账号。
  String get displayName => alias.isEmpty ? account : alias;

  Map<String, Object?> toJson() => <String, Object?>{
    'account': account,
    'alias': alias,
  };
}

/// 遥控会话列表存储：本机 SharedPreferences + 云端同步（按登录账号）。
///
/// 同步策略（已与用户确认）：
/// - 以**登录账号**为键，两台设备登录同一账号才共享列表；
/// - **服务端时间戳为准的全量覆盖（LWW）**：本机每次变更即上传整份，
///   打开会话页时拉取云端，云端更新则覆盖本机；删除同样随整份同步；
///   代价是两台设备离线期间各改各的，以最后一次上传为准。
class ThreadTargetsStore {
  ThreadTargetsStore._();

  static final ThreadTargetsStore instance = ThreadTargetsStore._();

  /// 新版键：JSON 字符串 {lastSyncAt, targets:[{account, alias}]}。
  static const String _keyV2 = 'remote_thread_targets_v2';

  /// 旧版键：纯账号字符串列表（迁移后删除）。
  static const String _keyLegacy = 'remote_thread_targets';

  static const String _url = '${AppConstants.toolsBaseUrl}/api/remote_sessions';

  final StreamController<void> _changes = StreamController<void>.broadcast();

  late SharedPreferences _prefs;
  bool _loaded = false;
  List<ThreadTarget> _targets = <ThreadTarget>[];

  /// 本机最后一次与云端对齐的时间（服务端 updatedAt）；null=从未同步。
  String? _lastSyncAt;

  /// 本机有改动尚未成功上传（上传失败时置位，下次同步补传）。
  bool _dirty = false;

  /// 列表变化通知（新增 / 改名 / 移除 / 云端覆盖后刷新会话列表）。
  Stream<void> get changes => _changes.stream;

  /// 已添加的目标（添加顺序）。
  List<ThreadTarget> get targets => List<ThreadTarget>.unmodifiable(_targets);

  /// 备注名；不存在返回 null。
  String? aliasOf(String account) {
    for (final ThreadTarget t in _targets) {
      if (t.account == account) return t.alias;
    }
    return null;
  }

  /// 展示名：有备注用备注，否则原始账号。
  String displayNameOf(String account) {
    final String? alias = aliasOf(account);
    return (alias == null || alias.isEmpty) ? account : alias;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loadLocal();
    _loaded = true;
  }

  void _loadLocal() {
    final String? raw = _prefs.getString(_keyV2);
    if (raw != null) {
      try {
        final Map<String, dynamic> map =
            jsonDecode(raw) as Map<String, dynamic>;
        _lastSyncAt = map['lastSyncAt'] as String?;
        _targets = _parseTargets(map['targets']);
        return;
      } catch (_) {
        // 落库格式损坏则按空列表处理，下面继续走旧数据迁移。
      }
    }
    // 旧数据迁移：stringList → [{account, alias:''}]。
    final List<String>? legacy = _prefs.getStringList(_keyLegacy);
    _targets = legacy == null
        ? <ThreadTarget>[]
        : legacy
            .where((String a) => a.trim().isNotEmpty)
            .map((String a) => ThreadTarget(account: a.trim()))
            .toList();
    _lastSyncAt = null;
    _prefs.remove(_keyLegacy);
    _persistLocal();
  }

  static List<ThreadTarget> _parseTargets(Object? raw) {
    if (raw is! List) return <ThreadTarget>[];
    final List<ThreadTarget> result = <ThreadTarget>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String account = '${item['account'] ?? ''}'.trim();
      if (account.isEmpty) continue;
      final String alias = '${item['alias'] ?? ''}';
      result.add(ThreadTarget(account: account, alias: alias));
    }
    return result;
  }

  Future<void> _persistLocal() async {
    await _prefs.setString(
      _keyV2,
      jsonEncode(<String, Object?>{
        'lastSyncAt': _lastSyncAt,
        'targets': _targets.map((ThreadTarget t) => t.toJson()).toList(),
      }),
    );
  }

  /// 添加目标；已存在则返回 false（不重复、不通知）。
  Future<bool> add(String account) async {
    await ensureLoaded();
    final String target = account.trim();
    if (target.isEmpty || _targets.any((ThreadTarget t) => t.account == target)) {
      return false;
    }
    _targets = <ThreadTarget>[..._targets, ThreadTarget(account: target)];
    await _persistLocal();
    _changes.add(null);
    _dirty = true;
    unawaited(_push());
    return true;
  }

  /// 移除目标（列表长按菜单「移除」）。
  Future<void> remove(String account) async {
    await ensureLoaded();
    if (!_targets.any((ThreadTarget t) => t.account == account)) return;
    _targets = _targets.where((ThreadTarget t) => t.account != account).toList();
    await _persistLocal();
    _changes.add(null);
    _dirty = true;
    unawaited(_push());
  }

  /// 改名（列表长按菜单「重命名」）；备注为空等价于恢复原始账号。
  Future<void> rename(String account, String alias) async {
    await ensureLoaded();
    final String trimmed = alias.trim();
    bool changed = false;
    _targets = _targets.map((ThreadTarget t) {
      if (t.account != account || t.alias == trimmed) return t;
      changed = true;
      return ThreadTarget(account: t.account, alias: trimmed);
    }).toList();
    if (!changed) return;
    await _persistLocal();
    _changes.add(null);
    _dirty = true;
    unawaited(_push());
  }

  /// 打开会话页时调用：拉取云端，按服务端时间戳 LWW 决定覆盖或上传。
  Future<void> syncFromServer() async {
    await ensureLoaded();
    try {
      final Map<String, dynamic>? remote = await _get();
      if (remote == null) return;
      final String? remoteAt = remote['updatedAt'] as String?;
      final List<ThreadTarget> remoteTargets = _parseTargets(remote['items']);

      if (remoteAt == null) {
        // 云端从未同步过 → 本机有数据就上传整份（含备注名）。
        if (_targets.isNotEmpty) await _push();
      } else if (_isNewer(remoteAt, _lastSyncAt)) {
        // 云端更新 → 全量覆盖本机（含删除）。
        _targets = remoteTargets;
        _lastSyncAt = remoteAt;
        await _persistLocal();
        _changes.add(null);
      } else if (_isNewer(_lastSyncAt, remoteAt) || _dirty) {
        // 本机更新（离线期间改过）或上次上传失败 → 上传覆盖云端。
        await _push();
      }
      // 时间戳一致 = 已对齐，无操作。
    } catch (_) {
      // 离线 / 未登录等一律静默：本地列表照常可用。
    }
  }

  /// 时间戳比较（ISO 字符串可按字典序比）；null 视为最旧。
  static bool _isNewer(String? a, String? b) {
    if (a == null) return false;
    if (b == null) return true;
    return a.compareTo(b) > 0;
  }

  /// 本机变更后上传整份；成功后记录服务端 updatedAt。
  Future<void> _push() async {
    try {
      final Map<String, dynamic>? data = await _post(
        _targets.map((ThreadTarget t) => t.toJson()).toList(),
      );
      final String? at = data?['updatedAt'] as String?;
      if (at != null) {
        _lastSyncAt = at;
        _dirty = false;
        await _persistLocal();
      }
    } catch (_) {
      // 上传失败静默；下次变更或打开会话页会再试。
    }
  }

  /// GET；失败（cookie 过期返回「请先登录」）则重登一次再取，仍失败抛出。
  Future<Map<String, dynamic>?> _get() async {
    try {
      return _decode(await PtoolsUtil.fetchUrl(_url));
    } catch (_) {
      if (await PtoolsUtil.loginWithSaved()) {
        return _decode(await PtoolsUtil.fetchUrl(_url, retryOnUnlogin: false));
      }
      rethrow;
    }
  }

  /// POST 整份列表；遇未登录（100000）重登后重试一次。
  Future<Map<String, dynamic>?> _post(List<Object?> items) async {
    try {
      return await _postOnce(items);
    } catch (_) {
      if (await PtoolsUtil.loginWithSaved()) return _postOnce(items);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _postOnce(List<Object?> items) async {
    final dynamic data = await DioManager().send(
      url: _url,
      method: HttpMethod.POST,
      params: <String, dynamic>{'items': items},
      contentType: 'application/json',
      notTipNetError: true,
      maxRetry: 1,
    );
    final String text = data is String ? data.trim() : jsonEncode(data);
    final dynamic decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const PtoolsException(PtoolsCode.failed, '同步响应格式错误');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
    final int code = _intOf(map['code']);
    if (code != PtoolsCode.success) {
      throw PtoolsException(code, '${map['msg'] ?? '同步失败'}');
    }
    final Object? body = map['data'];
    return body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
  }

  /// 解析服务端统一响应 {code, msg, data}；非成功码返回 null。
  static Map<String, dynamic>? _decode(Object? raw) {
    String text = '';
    if (raw is String) {
      text = raw.trim();
    } else if (raw != null) {
      text = jsonEncode(raw);
    }
    if (!text.startsWith('{')) return null;
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      if (_intOf(map['code']) != PtoolsCode.success) return null;
      final Object? data = map['data'];
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } catch (_) {
      return null;
    }
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? -1;
  }
}

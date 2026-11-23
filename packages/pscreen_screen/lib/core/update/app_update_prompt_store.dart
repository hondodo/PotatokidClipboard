import 'package:shared_preferences/shared_preferences.dart';

/// 记录「已提示过的普通更新版本」，供更新轻提示（吐司）按版本去重。
///
/// 去重口径：按 `appId + versionKey`。versionKey 通常是服务端下发的
/// `releaseId`（每次发布唯一）；调用方在 releaseId 缺失时退化成
/// `v{version}+{build}`。同一版本只提示一次，之后无论重启、回前台复检、
/// 缓存命中重新进入 ready 都不再提示；只有出现新版本（新 versionKey）
/// 才会再提示一次。
///
/// 强制更新不写这里：强更由 ForceUpdatePage 整页接管，每次都要拦，
/// 不能被「已经提示过」绕过。
class AppUpdatePromptStore {
  AppUpdatePromptStore(this._prefs);

  /// 提示记录键前缀。AppSettings 的 clearAllPersisted() 会跳过该前缀，
  /// 避免「重置设置」把记录清掉后又对同一版本重复提示。
  static const String keyPrefix = 'app_update_prompted_v1_';

  static Future<AppUpdatePromptStore> open() async =>
      AppUpdatePromptStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// 每个 appId 最多保留最近多少个已提示版本，避免列表无限增长。
  static const int _maxKeep = 20;

  String _key(String appId) => '$keyPrefix${appId.isEmpty ? '_' : appId}';

  /// 该版本是否已经提示过。空的 [versionKey] 恒返回 false（无法去重）。
  bool isPrompted(String appId, String versionKey) {
    if (versionKey.isEmpty) return false;
    return (_prefs.getStringList(_key(appId)) ?? const <String>[]).contains(
      versionKey,
    );
  }

  /// 标记该版本已提示。重复标记是幂等的；超过 [_maxKeep] 时裁掉最旧的。
  Future<void> markPrompted(String appId, String versionKey) async {
    if (versionKey.isEmpty) return;
    final List<String> list = List<String>.from(
      _prefs.getStringList(_key(appId)) ?? const <String>[],
    );
    if (list.contains(versionKey)) return;
    list.add(versionKey);
    if (list.length > _maxKeep) {
      list.removeRange(0, list.length - _maxKeep);
    }
    await _prefs.setStringList(_key(appId), list);
  }
}

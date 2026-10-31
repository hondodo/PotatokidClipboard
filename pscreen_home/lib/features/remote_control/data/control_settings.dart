import 'package:shared_preferences/shared_preferences.dart';

/// 持久化：管理员最近勾选的 TV 目标。
///
/// 账号 / 口令已迁移到共享包 `AppSettings`（`DeviceCredentials` 消费），
/// 这里的 `realtime_account` / `realtime_token` 仅作旧数据迁移来源保留读取。
class ControlSettings {
  ControlSettings._();

  static final ControlSettings instance = ControlSettings._();

  static const String _kAccount = 'realtime_account';
  static const String _kToken = 'realtime_token';
  static const String _kSelectedTvs = 'selected_tv_accounts';

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  /// 旧版遥控账号（迁移读取用；新值请写 `AppSettings.remoteAccount`）。
  String get account => _loaded ? (_prefs.getString(_kAccount) ?? '') : '';

  /// 旧版口令（迁移读取用；新值请写 `AppSettings.remotePassword`）。
  String get token =>
      _loaded ? (_prefs.getString(_kToken) ?? '12345678') : '12345678';

  /// 管理员最近勾选的目标账号列表。
  List<String> get selectedTvAccounts => _loaded
      ? (_prefs.getStringList(_kSelectedTvs) ?? const <String>[])
      : const <String>[];
  Future<void> setSelectedTvAccounts(List<String> value) =>
      _prefs.setStringList(_kSelectedTvs, value);
}

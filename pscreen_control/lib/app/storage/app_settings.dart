import 'package:shared_preferences/shared_preferences.dart';

/// 持久化：登录账号、token、管理员最近勾选的 TV 目标。
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAccount = 'nim_account';
  static const String _kToken = 'nim_token';
  static const String _kSelectedTvs = 'selected_tv_accounts';

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  String get nimAccount => _loaded ? (_prefs.getString(_kAccount) ?? '') : '';
  Future<void> setNimAccount(String value) =>
      _prefs.setString(_kAccount, value);

  String get nimToken =>
      _loaded ? (_prefs.getString(_kToken) ?? '12345678') : '12345678';
  Future<void> setNimToken(String value) =>
      _prefs.setString(_kToken, value);

  /// 管理员最近勾选的目标账号列表。
  List<String> get selectedTvAccounts => _loaded
      ? (_prefs.getStringList(_kSelectedTvs) ?? const <String>[])
      : const <String>[];
  Future<void> setSelectedTvAccounts(List<String> value) =>
      _prefs.setStringList(_kSelectedTvs, value);
}

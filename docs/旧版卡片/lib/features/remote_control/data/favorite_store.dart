import 'package:shared_preferences/shared_preferences.dart';

/// 直播频道收藏（按被控设备账号隔离）。
///
/// 收藏只在本机保存（`fav:<账号>`），不占用实时通道带宽；
/// 遥控面板长按频道项切换收藏。
class FavoriteStore {
  FavoriteStore._();

  static final FavoriteStore instance = FavoriteStore._();

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  String _key(String account) => 'fav:$account';

  /// 某设备的收藏频道名集合。
  Set<String> channelsOf(String account) =>
      _loaded
          ? Set<String>.from(_prefs.getStringList(_key(account)) ?? const <String>[])
          : const <String>{};

  Future<void> toggle(String account, String channelName) async {
    if (!_loaded || account.isEmpty || channelName.isEmpty) return;
    final Set<String> next = Set<String>.from(channelsOf(account));
    if (!next.remove(channelName)) next.add(channelName);
    await _prefs.setStringList(_key(account), next.toList());
  }
}

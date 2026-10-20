import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 连接配置的本地持久化存储。
///
/// 保存用户在设置页手动指定的 Home Assistant 地址 / 令牌
/// （部署到非本机设备时 .env 里的 `localhost` 不可达，必须可改）。
///
/// 约定：
/// - 存储值为**覆盖值**，空字符串表示「无覆盖」；
/// - 生效优先级：持久化覆盖 > `.env` 默认值（见 `AppConfig`）；
/// - 清空输入并保存即删除覆盖，回落到 `.env`。
///
/// `ready` 在 `StorageModule.register()` 中 await 完成，
/// 后续读取为同步内存访问。
class SettingsStore {
  SettingsStore();

  /// 覆盖值的 SharedPreferences 键
  static const String hostKey = 'ha_host_override';
  static const String tokenKey = 'ha_token_override';
  static const String powerSampleSecondsKey = 'power_sample_seconds';

  /// 功率采样间隔默认值（秒）。
  static const int defaultPowerSampleSeconds = 5;

  /// 可选的功率采样间隔（秒），设置页按此顺序展示。
  static const List<int> powerSampleOptions = <int>[1, 2, 3, 4, 5, 10, 30];

  SharedPreferences? _prefs;

  /// 初始化（DI 注册时调用一次；失败时降级为无覆盖）
  Future<void> init() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      Injection.get<LogService>().warn('读取本地配置失败，回落 .env 默认值：$e');
    }
  }

  /// 持久化的地址覆盖值（空 = 未覆盖，使用 .env）
  String get hostOverride => _prefs?.getString(hostKey) ?? '';

  /// 持久化的令牌覆盖值（空 = 未覆盖，使用 .env）
  String get tokenOverride => _prefs?.getString(tokenKey) ?? '';

  /// 功率采样间隔（秒）。未设置或非法值时回落 [defaultPowerSampleSeconds]。
  int get powerSampleSeconds {
    final int? value = _prefs?.getInt(powerSampleSecondsKey);
    if (value == null) return defaultPowerSampleSeconds;
    return powerSampleOptions.contains(value)
        ? value
        : defaultPowerSampleSeconds;
  }

  /// 持久化地址与令牌；空字符串表示删除覆盖（回落 .env）。
  Future<void> save({required String host, required String token}) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      if (host.isEmpty) {
        await prefs.remove(hostKey);
      } else {
        await prefs.setString(hostKey, host);
      }
      if (token.isEmpty) {
        await prefs.remove(tokenKey);
      } else {
        await prefs.setString(tokenKey, token);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入本地配置失败：$e');
    }
  }

  /// 持久化功率采样间隔；等于默认值时移除键（回落默认）。
  Future<void> savePowerSampleSeconds(int seconds) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      if (seconds == defaultPowerSampleSeconds ||
          !powerSampleOptions.contains(seconds)) {
        await prefs.remove(powerSampleSecondsKey);
      } else {
        await prefs.setInt(powerSampleSecondsKey, seconds);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入采样间隔失败：$e');
    }
  }
}

import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 连接配置的本地持久化存储。
///
/// 保存用户在设置页手动指定的 Home Assistant 地址 / 令牌
/// （部署到非本机设备时 .env 里的 `localhost` 不可达，必须可改）。
///
/// 约定：
/// - 存储值为**覆盖值**，空字符串表示「无覆盖」；
/// - 生效优先级：持久化覆盖 > `.env` 默认值（见 `HaConfig`）；
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

  /// 全局界面缩放倍数（1.0 = 原始尺寸，仅作用于本应用）。
  static const String uiScaleKey = 'ui_scale';

  /// 上次观看的直播频道名（下次进入直播页时恢复）。
  static const String lastLiveChannelKey = 'live_last_channel_v1';

  /// 15 寸 1920x1080 大屏的默认缩放：卡片/字号整体放大 1.5 倍。
  static const double defaultUiScale = 1.5;
  static const double minUiScale = 1.0;
  static const double maxUiScale = 2.0;

  /// 收敛到合法范围，避免读到脏数据后界面被放大到不可用。
  static double normalizeUiScale(double value) =>
      value.clamp(minUiScale, maxUiScale).toDouble();

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

  /// 全局界面缩放倍数（未设置时回落 [defaultUiScale]）。
  double get uiScale {
    final double? value = _prefs?.getDouble(uiScaleKey);
    if (value == null) return defaultUiScale;
    return normalizeUiScale(value);
  }

  /// 上次观看的直播频道名（空串 = 未记录）。
  String get lastLiveChannel => _prefs?.getString(lastLiveChannelKey) ?? '';

  /// 持久化界面缩放；等于默认值时移除键（回落默认）。
  Future<void> saveUiScale(double value) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      final double next = normalizeUiScale(value);
      if ((next - defaultUiScale).abs() < 0.001) {
        await prefs.remove(uiScaleKey);
      } else {
        await prefs.setDouble(uiScaleKey, next);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入界面缩放失败：$e');
    }
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

  /// 持久化上次观看的直播频道名；空串表示清除。
  Future<void> saveLastLiveChannel(String name) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      if (name.isEmpty) {
        await prefs.remove(lastLiveChannelKey);
      } else {
        await prefs.setString(lastLiveChannelKey, name);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入上次直播频道失败：$e');
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

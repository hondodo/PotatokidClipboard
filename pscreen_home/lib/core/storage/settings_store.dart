import 'dart:convert';

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
  static const String serverBaseUrlKey = 'server_base_url_override';
  static const String powerSampleSecondsKey = 'power_sample_seconds';

  /// 功率采样间隔默认值（秒）。
  static const int defaultPowerSampleSeconds = 5;

  /// 可选的功率采样间隔（秒），设置页按此顺序展示。
  static const List<int> powerSampleOptions = <int>[1, 2, 3, 4, 5, 10, 30];

  /// 屏保空闲时长（分钟）的持久化键。
  static const String screensaverMinutesKey = 'screensaver_minutes_v1';

  /// 屏保默认空闲时长（分钟）。
  static const int defaultScreensaverMinutes = 10;

  /// 屏保「从不」选项：0 表示不自动进入屏保。
  static const int screensaverNeverMinutes = 0;

  /// 可选的屏保空闲时长（分钟），设置页按此顺序展示。
  static const List<int> screensaverOptions = <int>[
    1,
    5,
    10,
    15,
    20,
    30,
    45,
    60,
    screensaverNeverMinutes,
  ];

  /// 屏保壁纸是否开启的持久化键。
  static const String wallpaperEnabledKey = 'wallpaper_enabled_v1';

  /// 屏保壁纸默认开启。
  static const bool defaultWallpaperEnabled = true;

  /// 屏保壁纸 API 的持久化键。
  static const String wallpaperApiUrlKey = 'wallpaper_api_url_v1';

  /// 默认壁纸 API：真实风景照片（302 跳转到随机图片）。
  ///
  /// Uapis 的 `category=landscape` 会聚合多个外部图源，其中仍可能混入
  /// 动漫/幻想插画；这里直接使用其风景图源，保证屏保是真实照片。
  /// 需要 Uapis 随机壁纸时可在设置页填：
  /// `https://uapis.cn/api/v1/random/image?category=landscape`
  static const String defaultWallpaperApiUrl =
      'https://tu.ltyuanfang.cn/api/fengjing.php';

  /// 壁纸刷新间隔（分钟）的持久化键。
  static const String wallpaperMinutesKey = 'wallpaper_refresh_minutes_v1';

  /// 壁纸默认刷新间隔（分钟）。
  static const int defaultWallpaperMinutes = 30;

  /// 可选的壁纸刷新间隔（分钟），设置页按此顺序展示。
  static const List<int> wallpaperMinuteOptions = <int>[
    5,
    10,
    30,
    60,
    720,
    1440,
  ];

  /// 壁纸刷新间隔的中文标签。
  static String wallpaperMinuteLabel(int minutes) {
    if (minutes == 720) return '半天';
    if (minutes == 1440) return '1 天';
    return '$minutes 分钟';
  }

  /// 全局界面缩放倍数（1.0 = 原始尺寸，仅作用于本应用）。
  static const String uiScaleKey = 'ui_scale';

  /// 上次观看的直播频道名（下次进入直播页时恢复）。
  static const String lastLiveChannelKey = 'live_last_channel_v1';

  /// 主页卡片在「全部」视图下的拖拽顺序（设备/实体稳定 key）。
  static const String cardOrderAllKey = 'home_card_order_all_v1';

  /// 主页卡片在每个家庭下的拖拽顺序，JSON：`{ "金科1204": ["device:..."] }`。
  ///
  /// 房间不单独存：房间视图直接过滤所属家庭的顺序。
  static const String cardOrderByHomeKey = 'home_card_order_by_home_v1';

  /// 卡片顺序最后一次本地修改时间（毫秒），用于与服务端布局做新旧比较。
  static const String cardOrderUpdatedAtKey = 'home_card_order_updated_at_v1';

  /// HA 注册表快照（房间 / 设备 / 实体归属），用于拉取失败时兜底。
  ///
  /// 值由 data 层编码为 JSON；这里只负责原样存取，避免存储层依赖领域模型。
  static const String registryCacheKey = 'ha_registry_cache_v1';

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

  /// 持久化的管理服务端地址覆盖值（空 = 未覆盖，使用 .env）。
  String get serverBaseUrlOverride =>
      _prefs?.getString(serverBaseUrlKey) ?? '';

  /// 功率采样间隔（秒）。未设置或非法值时回落 [defaultPowerSampleSeconds]。
  int get powerSampleSeconds {
    final int? value = _prefs?.getInt(powerSampleSecondsKey);
    if (value == null) return defaultPowerSampleSeconds;
    return powerSampleOptions.contains(value)
        ? value
        : defaultPowerSampleSeconds;
  }

  /// 屏保空闲时长（分钟）。未设置或非法值时回落
  /// [defaultScreensaverMinutes]。
  int get screensaverMinutes {
    final int? value = _prefs?.getInt(screensaverMinutesKey);
    if (value == null || !screensaverOptions.contains(value)) {
      return defaultScreensaverMinutes;
    }
    return value;
  }

  /// 屏保壁纸是否开启（未设置时默认开启）。
  bool get wallpaperEnabled =>
      _prefs?.getBool(wallpaperEnabledKey) ?? defaultWallpaperEnabled;

  /// 屏保壁纸 API 地址（未设置或为空时回落默认风景接口）。
  String get wallpaperApiUrl {
    final String? value = _prefs?.getString(wallpaperApiUrlKey);
    if (value == null || value.trim().isEmpty) {
      return defaultWallpaperApiUrl;
    }
    return value.trim();
  }

  /// 壁纸刷新间隔（分钟）。未设置或非法值时回落
  /// [defaultWallpaperMinutes]。
  int get wallpaperMinutes {
    final int? value = _prefs?.getInt(wallpaperMinutesKey);
    if (value == null || !wallpaperMinuteOptions.contains(value)) {
      return defaultWallpaperMinutes;
    }
    return value;
  }

  /// 全局界面缩放倍数（未设置时回落 [defaultUiScale]）。
  double get uiScale {
    final double? value = _prefs?.getDouble(uiScaleKey);
    if (value == null) return defaultUiScale;
    return normalizeUiScale(value);
  }

  /// 上次观看的直播频道名（空串 = 未记录）。
  String get lastLiveChannel => _prefs?.getString(lastLiveChannelKey) ?? '';

  /// 「全部」视图的卡片顺序（未设置时为空，界面回落默认排序）。
  List<String> get cardOrderAll =>
      _prefs?.getStringList(cardOrderAllKey) ?? const <String>[];

  /// 卡片顺序最后一次修改时间（毫秒；0 = 从未保存）。
  int get cardOrderUpdatedAt => _prefs?.getInt(cardOrderUpdatedAtKey) ?? 0;

  /// 注册表缓存的原始 JSON（空串 = 尚未缓存）。
  String get registryCacheRaw => _prefs?.getString(registryCacheKey) ?? '';

  /// 每个家庭各自的卡片顺序（未设置/损坏时为空）。
  Map<String, List<String>> get cardOrderByHome {
    final String? raw = _prefs?.getString(cardOrderByHomeKey);
    if (raw == null || raw.isEmpty) return const <String, List<String>>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, List<String>>{};
      final Map<String, List<String>> result = <String, List<String>>{};
      decoded.forEach((Object? key, Object? value) {
        if (key is String && value is List) {
          result[key] = value.whereType<String>().toList(growable: false);
        }
      });
      return result;
    } catch (e) {
      Injection.get<LogService>().warn('读取卡片顺序失败，回落默认排序：$e');
      return const <String, List<String>>{};
    }
  }

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

  /// 持久化管理服务端地址；空字符串表示删除覆盖（回落 .env）。
  Future<void> saveServerBaseUrl(String url) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      final String value = url.trim();
      if (value.isEmpty) {
        await prefs.remove(serverBaseUrlKey);
      } else {
        await prefs.setString(serverBaseUrlKey, value);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入服务端地址失败：$e');
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

  /// 持久化主页卡片顺序（「全部」+ 每个家庭）。
  ///
  /// 空列表写为空数组；下次读取时界面会按默认排序补齐。
  /// [updatedAt] 用于与服务端布局比较新旧，缺省取当前时间。
  Future<void> saveCardOrders({
    required List<String> all,
    required Map<String, List<String>> byHome,
    int? updatedAt,
  }) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setStringList(cardOrderAllKey, all);
      await prefs.setString(cardOrderByHomeKey, jsonEncode(byHome));
      await prefs.setInt(
        cardOrderUpdatedAtKey,
        updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      Injection.get<LogService>().warn('写入卡片顺序失败：$e');
    }
  }

  /// 持久化注册表缓存；空串表示清除。
  Future<void> saveRegistryCacheRaw(String raw) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      if (raw.isEmpty) {
        await prefs.remove(registryCacheKey);
      } else {
        await prefs.setString(registryCacheKey, raw);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入注册表缓存失败：$e');
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

  /// 持久化屏保空闲时长；默认值移除键，非法值忽略。
  Future<void> saveScreensaverMinutes(int minutes) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    if (!screensaverOptions.contains(minutes)) return;
    try {
      if (minutes == defaultScreensaverMinutes) {
        await prefs.remove(screensaverMinutesKey);
      } else {
        await prefs.setInt(screensaverMinutesKey, minutes);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入屏保时长失败：$e');
    }
  }

  /// 持久化壁纸开关；默认值（开启）移除键。
  Future<void> saveWallpaperEnabled(bool enabled) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      if (enabled == defaultWallpaperEnabled) {
        await prefs.remove(wallpaperEnabledKey);
      } else {
        await prefs.setBool(wallpaperEnabledKey, enabled);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入壁纸开关失败：$e');
    }
  }

  /// 持久化壁纸 API；空值或默认值移除键。
  Future<void> saveWallpaperApiUrl(String url) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    try {
      final String next = url.trim();
      if (next.isEmpty || next == defaultWallpaperApiUrl) {
        await prefs.remove(wallpaperApiUrlKey);
      } else {
        await prefs.setString(wallpaperApiUrlKey, next);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入壁纸 API 失败：$e');
    }
  }

  /// 持久化壁纸刷新间隔；默认值移除键，非法值忽略。
  Future<void> saveWallpaperMinutes(int minutes) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    if (!wallpaperMinuteOptions.contains(minutes)) return;
    try {
      if (minutes == defaultWallpaperMinutes) {
        await prefs.remove(wallpaperMinutesKey);
      } else {
        await prefs.setInt(wallpaperMinutesKey, minutes);
      }
    } catch (e) {
      Injection.get<LogService>().warn('写入壁纸刷新间隔失败：$e');
    }
  }
}

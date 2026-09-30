import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';

/// 应用级设置持久化（全局单例）。
///
/// 负责「我的」页面所有设置项的读写，包括：
/// - 主题模式（themeMode）
/// - 悬浮遥控器显隐（showFloatingRemote）
/// - 悬浮遥控器锁定（floatingRemoteLocked）
/// - 硬件解码开关（hwdecEnabled）
/// - 画面显示模式（aspectMode）
/// - 天气城市（weatherCity）
/// - 清理失效源开关（removeInvalidSources）
/// - 代理重试开关（proxyRetryEnabled）
///
/// 语言设置由 easy_localization 自行持久化，不在此处管理。
class AppSettings {
  AppSettings._();

  /// 全局单例。
  static final AppSettings instance = AppSettings._();

  static const String _keyThemeMode = 'app_theme_mode_v1';
  static const String _keyFloatingRemote = 'app_floating_remote_v1';
  static const String _keyFloatingRemoteLocked = 'app_floating_remote_locked_v1';
  static const String _keyHwdec = 'app_hwdec_v1';
  static const String _keyAspectMode = 'app_aspect_mode_v1';
  static const String _keyWeatherCity = 'app_weather_city_v1';
  static const String _keyRemoveInvalidSources = 'app_remove_invalid_sources_v1';
  static const String _keyProxyRetry = 'app_proxy_retry_v1';

  /// 首次加载的 Future；并发调用共享同一次加载，避免第二个调用提前返回旧值。
  Future<void>? _loading;

  /// 主题模式默认**深色**（未持久化过任何选择时生效，用户可在「我的」页改）。
  ThemeMode _themeMode = ThemeMode.dark;
  bool _showFloatingRemote = false;

  /// 悬浮遥控器是否锁定（锁定后不跟随顶部导航条隐藏），默认**未锁**。
  bool _floatingRemoteLocked = false;

  /// 默认关闭硬解：小米盒子等 Amlogic 芯片 TV 设备硬解路径兼容性差，
  /// 软解（FFmpeg）更稳定，用户可在「我的」页手动开启。
  bool _hwdecEnabled = false;

  /// 画面显示模式，默认「原始」。
  VideoAspectMode _aspectMode = VideoAspectMode.original;

  /// 天气城市名；**空串表示「自动」**（IP 反查定位）。
  String _weatherCity = '';

  /// 清理失效源：默认**关闭**（开启后连续打不开的地址会被记录并移除）。
  bool _removeInvalidSources = false;

  /// 代理重试：默认**关闭**（开启后直连失败的源会用免费代理重试一次）。
  bool _proxyRetryEnabled = false;

  ThemeMode get themeMode => _themeMode;
  bool get showFloatingRemote => _showFloatingRemote;

  /// 悬浮遥控器是否锁定（锁定后不跟随顶部导航条隐藏）。
  bool get floatingRemoteLocked => _floatingRemoteLocked;
  bool get hwdecEnabled => _hwdecEnabled;
  VideoAspectMode get aspectMode => _aspectMode;

  /// 天气城市：空串表示「自动」（IP 反查定位）。
  String get weatherCity => _weatherCity;

  /// 是否开启「清理失效源」。
  bool get removeInvalidSources => _removeInvalidSources;

  /// 是否开启「代理重试」。
  bool get proxyRetryEnabled => _proxyRetryEnabled;

  /// 从 SharedPreferences 加载所有设置（仅首次调用时真正读取）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 主题
      final String? themeRaw = prefs.getString(_keyThemeMode);
      if (themeRaw != null) {
        _themeMode = _themeModeFromString(themeRaw);
      }

      // 悬浮遥控器
      _showFloatingRemote = prefs.getBool(_keyFloatingRemote) ?? false;

      // 悬浮遥控器锁定
      _floatingRemoteLocked = prefs.getBool(_keyFloatingRemoteLocked) ?? false;

      // 硬解
      _hwdecEnabled = prefs.getBool(_keyHwdec) ?? false;

      // 画面显示模式
      _aspectMode = VideoAspectMode.fromName(prefs.getString(_keyAspectMode));

      // 天气城市：不在当前 .env 配置列表内（配置已改）则回退「自动」。
      final String city = prefs.getString(_keyWeatherCity) ?? '';
      _weatherCity = AppConfig.weatherCities.contains(city) ? city : '';

      // 清理失效源
      _removeInvalidSources = prefs.getBool(_keyRemoveInvalidSources) ?? false;

      // 代理重试
      _proxyRetryEnabled = prefs.getBool(_keyProxyRetry) ?? false;
    } catch (_) {
      // 读取失败则使用默认值。
    }
  }

  /// 保存主题模式。
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, _themeModeToString(mode));
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存悬浮遥控器显隐。
  Future<void> setShowFloatingRemote(bool show) async {
    _showFloatingRemote = show;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFloatingRemote, show);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存悬浮遥控器锁定状态。
  Future<void> setFloatingRemoteLocked(bool locked) async {
    _floatingRemoteLocked = locked;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFloatingRemoteLocked, locked);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存硬解开关。
  Future<void> setHwdecEnabled(bool enabled) async {
    _hwdecEnabled = enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHwdec, enabled);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存画面显示模式。
  Future<void> setAspectMode(VideoAspectMode mode) async {
    _aspectMode = mode;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAspectMode, mode.name);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存天气城市（空串表示「自动」）。
  Future<void> setWeatherCity(String city) async {
    _weatherCity = city;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyWeatherCity, city);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存「清理失效源」开关。
  Future<void> setRemoveInvalidSources(bool enabled) async {
    _removeInvalidSources = enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyRemoveInvalidSources, enabled);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 保存「代理重试」开关。
  Future<void> setProxyRetryEnabled(bool enabled) async {
    _proxyRetryEnabled = enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyProxyRetry, enabled);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }

  /// 清空**全部**持久化缓存并把内存中的设置恢复为默认值。
  ///
  /// 设置页「重置」使用：清空后立即重启应用，等同于首次安装。
  /// 采用「先取全部键再逐个删除」而非 `clear()`：语义可控、不与
  /// SharedPreferences 插件的缓存写回混在一起，且删除是异步落盘的，
  /// 必须 await 完成后才允许重启，否则重启后可能读到旧值。
  ///
  /// 持久化内容目前**全部**在 SharedPreferences 里（主题/语言之外的所有设置项、
  /// 频道列表缓存、频道源记忆、失效源黑名单、天气定位），故清空它即清空所有选项。
  Future<void> clearAllPersisted() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String key in prefs.getKeys().toList(growable: false)) {
        await prefs.remove(key);
      }
    } catch (_) {
      // 删除失败不阻断：后续重启仍会重新读取能读到的值。
    }
    _loading = null;
    _themeMode = ThemeMode.dark;
    _showFloatingRemote = false;
    _floatingRemoteLocked = false;
    _hwdecEnabled = false;
    _aspectMode = VideoAspectMode.original;
    _weatherCity = '';
    _removeInvalidSources = false;
    _proxyRetryEnabled = false;
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  static ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

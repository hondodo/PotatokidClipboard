import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';

/// 应用级设置持久化（全局单例）。
///
/// 负责「我的」页面所有设置项的读写，包括：
/// - 主题模式（themeMode）
/// - 悬浮遥控器显隐（showFloatingRemote）
/// - 硬件解码开关（hwdecEnabled）
/// - 画面显示模式（aspectMode）
///
/// 语言设置由 easy_localization 自行持久化，不在此处管理。
class AppSettings {
  AppSettings._();

  /// 全局单例。
  static final AppSettings instance = AppSettings._();

  static const String _keyThemeMode = 'app_theme_mode_v1';
  static const String _keyFloatingRemote = 'app_floating_remote_v1';
  static const String _keyHwdec = 'app_hwdec_v1';
  static const String _keyAspectMode = 'app_aspect_mode_v1';

  bool _loaded = false;

  ThemeMode _themeMode = ThemeMode.system;
  bool _showFloatingRemote = false;

  /// 默认关闭硬解：小米盒子等 Amlogic 芯片 TV 设备硬解路径兼容性差，
  /// 软解（FFmpeg）更稳定，用户可在「我的」页手动开启。
  bool _hwdecEnabled = false;

  /// 画面显示模式，默认「原始」。
  VideoAspectMode _aspectMode = VideoAspectMode.original;

  ThemeMode get themeMode => _themeMode;
  bool get showFloatingRemote => _showFloatingRemote;
  bool get hwdecEnabled => _hwdecEnabled;
  VideoAspectMode get aspectMode => _aspectMode;

  /// 从 SharedPreferences 加载所有设置（仅首次调用时真正读取）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 主题
      final String? themeRaw = prefs.getString(_keyThemeMode);
      if (themeRaw != null) {
        _themeMode = _themeModeFromString(themeRaw);
      }

      // 悬浮遥控器
      _showFloatingRemote = prefs.getBool(_keyFloatingRemote) ?? false;

      // 硬解
      _hwdecEnabled = prefs.getBool(_keyHwdec) ?? false;

      // 画面显示模式
      _aspectMode = VideoAspectMode.fromName(prefs.getString(_keyAspectMode));
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

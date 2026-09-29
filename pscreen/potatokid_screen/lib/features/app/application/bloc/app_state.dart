import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';

/// 应用级全局状态（不可变，通过 copyWith 更新）
class AppState {
  const AppState._({
    required this.themeMode,
    required this.isChromeVisible,
    required this.showFloatingRemote,
    required this.showChannels,
    required this.hwdecEnabled,
    required this.aspectMode,
    required this.weatherCity,
  });

  /// 初始状态：主题默认**深色**（用户可在「我的」页改为浅色/跟随系统），
  /// 导航条与频道条默认可见，
  /// 悬浮遥控器默认**隐藏**（需在「我的」页开启），
  /// 硬解默认**关闭**（TV 设备兼容性考虑，用户可在「我的」页开启）。
  factory AppState.initial() => const AppState._(
    themeMode: ThemeMode.dark,
    isChromeVisible: true,
    showFloatingRemote: false,
    showChannels: true,
    hwdecEnabled: false,
    aspectMode: VideoAspectMode.original,
    weatherCity: '',
  );

  final ThemeMode themeMode;

  /// AppBar 与底部导航栏（顶部 tab 条）是否可见（false 时进入沉浸式全屏）
  final bool isChromeVisible;

  /// 是否显示悬浮遥控器蒙层（手机调试用）
  final bool showFloatingRemote;

  /// 首页频道条是否可见（OK 随 [isChromeVisible] 一起同步；菜单键单独切换）
  final bool showChannels;

  /// 是否启用硬件解码（关闭时使用 FFmpeg 软解，TV 设备兼容性更好）
  final bool hwdecEnabled;

  /// 视频画面显示模式（原始/拉伸/16:9/4:3/21:9）
  final VideoAspectMode aspectMode;

  /// 天气城市名；空串表示「自动」（IP 反查定位）
  final String weatherCity;

  AppState copyWith({
    ThemeMode? themeMode,
    bool? isChromeVisible,
    bool? showFloatingRemote,
    bool? showChannels,
    bool? hwdecEnabled,
    VideoAspectMode? aspectMode,
    String? weatherCity,
  }) => AppState._(
        themeMode: themeMode ?? this.themeMode,
        isChromeVisible: isChromeVisible ?? this.isChromeVisible,
        showFloatingRemote: showFloatingRemote ?? this.showFloatingRemote,
        showChannels: showChannels ?? this.showChannels,
        hwdecEnabled: hwdecEnabled ?? this.hwdecEnabled,
        aspectMode: aspectMode ?? this.aspectMode,
        weatherCity: weatherCity ?? this.weatherCity,
      );
}

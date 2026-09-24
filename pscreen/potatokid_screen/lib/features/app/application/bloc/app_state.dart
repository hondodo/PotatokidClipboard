import 'package:flutter/material.dart';

/// 应用级全局状态（不可变，通过 copyWith 更新）
class AppState {
  const AppState._({
    required this.themeMode,
    required this.isChromeVisible,
    required this.showFloatingRemote,
    required this.showChannels,
  });

  /// 初始状态：跟随系统主题，导航条与频道条默认可见，
  /// 悬浮遥控器默认**隐藏**（需在「我的」页开启）。
  factory AppState.initial() => const AppState._(
    themeMode: ThemeMode.system,
    isChromeVisible: true,
    showFloatingRemote: false,
    showChannels: true,
  );

  final ThemeMode themeMode;

  /// AppBar 与底部导航栏（顶部 tab 条）是否可见（false 时进入沉浸式全屏）
  final bool isChromeVisible;

  /// 是否显示悬浮遥控器蒙层（手机调试用）
  final bool showFloatingRemote;

  /// 首页频道条是否可见（OK 随 [isChromeVisible] 一起同步；菜单键单独切换）
  final bool showChannels;

  AppState copyWith({
    ThemeMode? themeMode,
    bool? isChromeVisible,
    bool? showFloatingRemote,
    bool? showChannels,
  }) => AppState._(
        themeMode: themeMode ?? this.themeMode,
        isChromeVisible: isChromeVisible ?? this.isChromeVisible,
        showFloatingRemote: showFloatingRemote ?? this.showFloatingRemote,
        showChannels: showChannels ?? this.showChannels,
      );
}

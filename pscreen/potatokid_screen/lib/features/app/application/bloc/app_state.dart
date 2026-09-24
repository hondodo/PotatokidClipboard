import 'package:flutter/material.dart';

/// 应用级全局状态（不可变，通过 copyWith 更新）
class AppState {
  const AppState._({
    required this.themeMode,
    required this.isChromeVisible,
  });

  /// 初始状态：跟随系统主题，AppBar 与底部导航栏默认可见
  factory AppState.initial() => const AppState._(
    themeMode: ThemeMode.system,
    isChromeVisible: true,
  );

  final ThemeMode themeMode;

  /// AppBar 与底部导航栏是否可见（false 时进入沉浸式全屏）
  final bool isChromeVisible;

  AppState copyWith({ThemeMode? themeMode, bool? isChromeVisible}) =>
      AppState._(
        themeMode: themeMode ?? this.themeMode,
        isChromeVisible: isChromeVisible ?? this.isChromeVisible,
      );
}

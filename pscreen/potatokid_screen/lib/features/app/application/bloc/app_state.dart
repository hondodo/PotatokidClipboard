import 'package:flutter/material.dart';

/// 应用级全局状态（不可变，通过 copyWith 更新）
class AppState {
  const AppState._({required this.themeMode});

  /// 初始状态：跟随系统
  factory AppState.initial() => const AppState._(themeMode: ThemeMode.system);

  final ThemeMode themeMode;

  AppState copyWith({ThemeMode? themeMode}) =>
      AppState._(themeMode: themeMode ?? this.themeMode);
}

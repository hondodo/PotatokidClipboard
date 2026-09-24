import 'package:flutter/material.dart';

/// 应用级事件基类
abstract class AppEvent {
  const AppEvent();
}

/// 切换主题模式
class ChangeThemeMode extends AppEvent {
  const ChangeThemeMode(this.themeMode);

  final ThemeMode themeMode;
}

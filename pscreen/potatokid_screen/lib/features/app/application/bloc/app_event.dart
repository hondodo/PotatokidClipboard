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

/// 切换 AppBar / 底部导航栏的显隐（沉浸式全屏开关）
class ToggleChrome extends AppEvent {
  const ToggleChrome();
}

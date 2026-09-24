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

/// 切换 AppBar / 底部导航栏的显隐（沉浸式全屏开关）。
/// 顶部 tab 条与首页频道条一起显隐。
class ToggleChrome extends AppEvent {
  const ToggleChrome();
}

/// 单独切换首页频道条的显隐（菜单键呼出频道列表用）。
class ToggleChannels extends AppEvent {
  const ToggleChannels();
}

/// 设置是否显示悬浮遥控器蒙层
class SetFloatingRemote extends AppEvent {
  const SetFloatingRemote(this.show);

  final bool show;
}

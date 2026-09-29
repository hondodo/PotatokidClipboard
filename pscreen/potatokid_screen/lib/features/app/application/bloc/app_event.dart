import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';

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
/// 顶部 tab 条与首页频道条一起显隐（OK 键触发）。
class ToggleChrome extends AppEvent {
  const ToggleChrome();
}

/// 仅设置顶部 tab 条显隐，**不动**频道列表（供顶部条自动收起用，
/// 避免 10 秒自动收起把频道列表一起带走）。
class SetChrome extends AppEvent {
  const SetChrome(this.visible);

  final bool visible;
}

/// 仅设置首页频道列表显隐（供换台/滑动显示、30 秒无操作隐藏用）。
class SetChannels extends AppEvent {
  const SetChannels(this.show);

  final bool show;
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

/// 设置是否启用硬件解码
class SetHardwareDecode extends AppEvent {
  const SetHardwareDecode(this.enabled);

  final bool enabled;
}

/// 设置视频画面显示模式（原始/拉伸/16:9/4:3/21:9）
class ChangeAspectMode extends AppEvent {
  const ChangeAspectMode(this.mode);

  final VideoAspectMode mode;
}

/// 设置天气城市（空串表示「自动」，可选城市来自 `.env` 的 `WEATHER_CITIES`）
class ChangeWeatherCity extends AppEvent {
  const ChangeWeatherCity(this.city);

  final String city;
}

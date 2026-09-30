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

/// 仅设置顶部 tab 条显隐，**不动**频道列表（供菜单键/点屏切换、自动收起用）。
class SetChrome extends AppEvent {
  const SetChrome(this.visible);

  final bool visible;
}

/// 仅设置首页频道列表显隐（供换台/滑动显示、无操作自动隐藏、首页 OK 键切换用）。
class SetChannels extends AppEvent {
  const SetChannels(this.show);

  final bool show;
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

/// 设置是否开启「清理失效源」（默认关）
class SetRemoveInvalidSources extends AppEvent {
  const SetRemoveInvalidSources(this.enabled);

  final bool enabled;
}

/// 设置是否开启「代理重试」（默认关）
class SetProxyRetry extends AppEvent {
  const SetProxyRetry(this.enabled);

  final bool enabled;
}

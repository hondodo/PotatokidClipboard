import 'dart:async';

/// 天气事件基类。
abstract class WeatherEvent {
  const WeatherEvent();
}

/// 加载天气（重新 IP 反查定位 + 拉取）。
class LoadWeather extends WeatherEvent {
  const LoadWeather({this.completer});

  /// 供调用方 await 事件完成。
  final Completer<bool>? completer;
}

/// 清空天气数据（如切换场景需要）。
class ClearWeather extends WeatherEvent {
  const ClearWeather();
}
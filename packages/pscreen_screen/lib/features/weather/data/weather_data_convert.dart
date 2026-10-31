import 'package:flutter/material.dart';

class WeatherDataConvert {
  static String dayLabel(String date, String today) {
    if (date == today) return '今天';
    final DateTime? dt = DateTime.tryParse(date);
    if (dt == null) return '';
    const List<String> w = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return w[dt.weekday - 1];
  }

  /// 天气代码 → 图标（未匹配到中文文案时兜底用）。
  static String emoji(String code) {
    switch (code) {
      case 'CLEAR_DAY':
      case 'CLEAR_NIGHT':
        return '☀️';
      case 'PARTLY_CLOUDY_DAY':
      case 'PARTLY_CLOUDY_NIGHT':
        return '⛅';
      case 'CLOUDY':
        return '☁️';
      case 'LIGHT_RAIN':
      case 'MODERATE_RAIN':
      case 'HEAVY_RAIN':
      case 'STORM_RAIN':
      case 'RAIN':
        return '🌧️';
      case 'LIGHT_SNOW':
      case 'MODERATE_SNOW':
      case 'HEAVY_SNOW':
      case 'SNOW':
        return '🌨️';
      case 'SLEET':
        return '🌧️';
      case 'FOG':
      case 'LIGHT_HAZE':
      case 'MODERATE_HAZE':
      case 'HEAVY_HAZE':
      case 'DUST':
      case 'SAND':
        return '🌫️';
      case 'WIND':
      case 'GALE':
        return '💨';
      case 'THUNDER_SHOWER':
        return '⛈️';
      case 'HAIL':
        return '🌨️';
      default:
        return code;
    }
  }

  /// 心知天气现象图标（V3 数字码，带 @2x 高清变体）。
  ///
  /// 深色主题加载 `assets/weather/black`，浅色主题加载 `assets/weather/white`。
  /// code 为空或非数字码（如 V4 的字符串码）时回退到 `_emoji`。
  static Widget weatherIcon(BuildContext context, String code, {double size = 24}) {
    if (code.isEmpty) return const SizedBox.shrink();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final String folder = dark ? 'black' : 'white';
    return Image.asset(
      'assets/weather/$folder/$code@2x.png',
      width: size,
      height: size,
      errorBuilder: (BuildContext c, Object error, StackTrace? stack) =>
          Text(emoji(code), style: TextStyle(fontSize: size * 0.8)),
    );
  }
}

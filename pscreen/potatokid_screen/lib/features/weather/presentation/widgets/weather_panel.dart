import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_state.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气小组件：消费全局 [WeatherBloc]，在无数据时不占位、不挡内容。
///
/// 展示：城市 + 当前温度/天气 + 未来 3 天预报。半透明圆角，适合叠在
/// 时间页 / 屏保页 / 主页的彩色或播放背景上。
class WeatherPanel extends StatelessWidget {
  const WeatherPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      buildWhen: (WeatherState previous, WeatherState current) =>
          previous.data != current.data || previous.isLoading != current.isLoading,
      builder: (BuildContext context, WeatherState state) {
        final WeatherData? data = state.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();

        final WeatherNow? now = data.now;
        final List<WeatherDay> days = data.daily.take(3).toList();

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
              if (now case final WeatherNow n when n.temperature != null) ...<Widget>[
                _weatherIcon(context, n.skycon, size: 30),
                const SizedBox(width: 8),
                Text(
                  '${n.temperature!.round()}°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      n.text.isNotEmpty ? n.text : _emoji(n.skycon),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    if (n.city.isNotEmpty)
                      Text(
                        n.city,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
              ],
              ..._buildDays(context, days),
                ],
              ),
              // 免费版 V3 要求注明数据来源。
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '数据来源：心知天气',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 未来几天（今天起 3 天）：白天天气 + 最高/最低。
  List<Widget> _buildDays(BuildContext context, List<WeatherDay> days) {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return <Widget>[
      for (final WeatherDay d in days)
        Container(
          margin: const EdgeInsets.only(left: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _dayLabel(d.date, today),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                '${d.tempMin?.round() ?? '-'}°',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                '${d.tempMax?.round() ?? '-'}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              _weatherIcon(context, d.skycon, size: 22),
            ],
          ),
        ),
    ];
  }

  /// 心知天气现象图标（V3 数字码，带 @2x 高清变体）。
  ///
  /// 深色主题加载 `assets/weather/black`，浅色主题加载 `assets/weather/white`。
  /// code 为空或非数字码（如 V4 的字符串码）时回退到 `_emoji`。
  Widget _weatherIcon(
    BuildContext context,
    String code, {
    double size = 24,
  }) {
    if (code.isEmpty) return const SizedBox.shrink();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final String folder = dark ? 'black' : 'white';
    return Image.asset(
      'assets/weather/$folder/$code@2x.png',
      width: size,
      height: size,
      errorBuilder:
          (BuildContext c, Object error, StackTrace? stack) =>
              Text(_emoji(code), style: TextStyle(fontSize: size * 0.8)),
    );
  }

  String _dayLabel(String date, String today) {
    if (date == today) return '今';
    final DateTime? dt = DateTime.tryParse(date);
    if (dt == null) return '';
    const List<String> w = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return w[dt.weekday - 1];
  }

  /// 天气代码 → 图标（未匹配到中文文案时兜底用）。
  String _emoji(String code) {
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
}
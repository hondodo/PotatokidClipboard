import 'package:dio/dio.dart';
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/weather_http_client.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 城市数据无访问权限（AP010006：免费版不覆盖该城市）。
class CityAccessException implements Exception {
  const CityAccessException(this.location);

  final String location;

  @override
  String toString() => 'CityAccessException($location)';
}

/// 心知天气数据接口层：只负责「请求什么」，解析与业务由上层完成。
///
/// 当前走 V3（免费版）接口，`location` 用经纬度或城市名。
class WeatherApiService {
  WeatherApiService({WeatherHttpClient? client})
      : _client = client ?? WeatherHttpClient.instance;

  final WeatherHttpClient _client;

  /// 拉取实时 + 逐日预报，返回聚合结果。
  ///
  /// [location] 形如 "纬度:经度" 或城市名（如 "吴川"）。
  /// 若该城市不受免费版覆盖（AP010006），自动回退到
  /// [AppConfig.seniverseDefaultLocation] 获取数据。
  Future<WeatherData> fetchWeather(String location) async {
    try {
      return await _fetch(location);
    } on CityAccessException catch (e) {
      final String fallback = AppConfig.seniverseDefaultLocation;
      if (fallback.isNotEmpty && fallback != e.location) {
        const LogService().warn(
          '城市 ${e.location} 无访问权限，回退到默认城市 $fallback',
        );
        // 最后一次尝试，不再回退。
        return await _fetch(fallback);
      }
      rethrow;
    }
  }

  Future<WeatherData> _fetch(String location) async {
    WeatherNow? now;
    List<WeatherDay> daily = const <WeatherDay>[];
    bool cityAccessBlocked = false;

    // 实时与逐日为独立请求，逐项容错：任一项失败不影响另一项。
    try {
      final Map<String, dynamic> nowJson = await _client.get(
        '/weather/now.json',
        <String, dynamic>{'location': location},
      );
      now = parseWeatherNowV3(nowJson);
    } on Exception catch (e) {
      if (_isCityAccess(e)) cityAccessBlocked = true;
      const LogService().warn('实时天气不可用：$e');
    }

    try {
      final Map<String, dynamic> dailyJson = await _client.get(
        '/weather/daily.json',
        <String, dynamic>{'location': location, 'days': '4'},
      );
      daily = parseWeatherDailyV3(dailyJson);
    } on Exception catch (e) {
      if (_isCityAccess(e)) cityAccessBlocked = true;
      const LogService().warn('逐日预报不可用：$e');
    }

    if (now == null && daily.isEmpty) {
      if (cityAccessBlocked) throw CityAccessException(location);
      throw StateError('天气数据获取失败');
    }
    return WeatherData(now: now, daily: daily);
  }

  /// 是否为城市无访问权限错误（免费版对未覆盖城市返回 HTTP 403 + AP010006）。
  bool _isCityAccess(Exception e) {
    if (e is DioException && e.response?.statusCode == 403) {
      return '${e.response?.data}'.contains('AP010006');
    }
    return false;
  }
}
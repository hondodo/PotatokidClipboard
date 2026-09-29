import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/features/weather/data/datasources/remote/ip_geo_service.dart';
import 'package:potatokid_screen/features/weather/data/datasources/remote/weather_api_service.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';
import 'package:potatokid_screen/features/weather/domain/repositories/weather_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 天气仓库实现：定位（缓存 + IP 反查）+ 拉取天气。
class WeatherRepositoryImpl implements WeatherRepository {
  WeatherRepositoryImpl({WeatherApiService? api, IpGeoService? ipGeo})
      : _api = api ?? WeatherApiService(),
        _ipGeo = ipGeo ?? IpGeoService();

  static const String _keyLocation = 'weather_location_v1';

  final WeatherApiService _api;
  final IpGeoService _ipGeo;

  @override
  Future<String?> resolveLocation() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 复用已缓存位置，避免每次启动都重新 IP 反查。
    final String? cached = prefs.getString(_keyLocation);
    if (cached != null && cached.isNotEmpty) return cached;

    final GeoLocation? loc = await _ipGeo.locate();
    if (loc == null) {
      const LogService().warn('IP 反查定位失败：未拿到经纬度');
      return null;
    }

    final String locStr = '${loc.lat}:${loc.lon}';
    try {
      await prefs.setString(_keyLocation, locStr);
    } catch (_) {
      // 缓存失败不影响本次使用。
    }
    return locStr;
  }

  @override
  Future<WeatherData> fetchWeather(String location) => _api.fetchWeather(location);
}
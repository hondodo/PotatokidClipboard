import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/weather/data/datasources/remote/ip_geo_service.dart';
import 'package:potatokid_screen/features/weather/data/datasources/remote/weather_api_service.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';
import 'package:potatokid_screen/features/weather/domain/repositories/weather_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 天气仓库实现：定位（手动城市 / IP 反查 + 缓存兜底）+ 拉取天气。
class WeatherRepositoryImpl implements WeatherRepository {
  WeatherRepositoryImpl({WeatherApiService? api, IpGeoService? ipGeo})
      : _api = api ?? WeatherApiService(),
        _ipGeo = ipGeo ?? IpGeoService();

  static const String _keyLocation = 'weather_location_v1';

  final WeatherApiService _api;
  final IpGeoService _ipGeo;

  /// 解析天气查询用的位置。
  ///
  /// - 「我的」页选了固定城市 → 直接返回该城市名，不做 IP 反查；
  /// - 选「自动」（城市名为空）→ 每次重新 IP 反查，换网络/换出口 IP 后位置能
  ///   自动纠正，缓存仅在反查失败时作为兜底，避免瞬时失败导致定位丢失。
  @override
  Future<String?> resolveLocation() async {
    // 设置在 AppBloc 构造时异步加载，这里确保读取前已完成。
    await AppSettings.instance.ensureLoaded();

    final String fixedCity = AppSettings.instance.weatherCity;
    if (fixedCity.isNotEmpty) return fixedCity;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString(_keyLocation);

    final GeoLocation? loc = await _ipGeo.locate();
    if (loc == null) {
      const LogService().warn('IP 反查定位失败：未拿到经纬度');
      return (cached != null && cached.isNotEmpty) ? cached : null;
    }

    final String locStr = '${loc.lat}:${loc.lon}';
    // 位置未变化时不重复写盘。
    if (locStr != cached) {
      try {
        await prefs.setString(_keyLocation, locStr);
      } catch (_) {
        // 缓存失败不影响本次使用。
      }
    }
    return locStr;
  }

  @override
  Future<WeatherData> fetchWeather(String location) => _api.fetchWeather(location);
}
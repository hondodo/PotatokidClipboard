import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气领域仓库接口（纯抽象）。
abstract class WeatherRepository {
  /// 解析天气查询用的位置，返回 "纬度:经度" 或城市名；失败返回 null。
  ///
  /// 「我的」页选了固定城市时直接返回城市名；选「自动」时每次 IP 反查定位
  /// （反查失败回退上次缓存的位置）。
  Future<String?> resolveLocation();

  /// 拉取指定位置（"纬度:经度" 或城市名）的实时 + 逐日天气。
  Future<WeatherData> fetchWeather(String location);
}
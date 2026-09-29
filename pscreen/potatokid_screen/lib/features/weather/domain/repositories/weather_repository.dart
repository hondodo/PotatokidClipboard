import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气领域仓库接口（纯抽象）。
abstract class WeatherRepository {
  /// 解析设备位置，返回形如 "纬度:经度" 的字符串；失败返回 null。
  ///
  /// 内部优先复用已缓存的位置，其次 IP 反查。
  Future<String?> resolveLocation();

  /// 拉取指定位置（"纬度:经度"）的实时 + 逐日天气。
  Future<WeatherData> fetchWeather(String location);
}
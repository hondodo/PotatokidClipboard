import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/http_base_request.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
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
/// 走 V3（免费版）接口，复用全局网络层（[HttpBaseRequest] → DioManager），
/// `location` 用经纬度或城市名。
class WeatherApiService {
  /// 拉取实时 + 逐日预报，返回聚合结果。
  ///
  /// [location] 形如 "纬度:经度" 或城市名（如 "湛江"）。
  /// 若该城市不受免费版覆盖（AP010006），自动回退到
  /// [AppConfig.seniverseDefaultLocation] 获取数据。
  Future<WeatherData> fetchWeather(String location) async {
    try {
      return await _fetch(location);
    } on CityAccessException catch (e) {
      final String fallback = AppConfig.seniverseDefaultLocation;
      if (fallback.isNotEmpty && fallback != e.location) {
        const LogService().warn('城市 ${e.location} 无访问权限，回退到默认城市 $fallback');
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
      final dynamic raw = await _WeatherNowRequest(location).send(2);
      if (raw is Map) {
        now = parseWeatherNowV3(_toStringKeyMap(raw));
      }
    } on Exception catch (e) {
      if (_isCityAccess(e)) cityAccessBlocked = true;
      const LogService().warn('实时天气不可用：$e');
    }

    try {
      final dynamic raw = await _WeatherDailyRequest(location).send(2);
      if (raw is Map) {
        daily = parseWeatherDailyV3(_toStringKeyMap(raw));
      }
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

  /// 是否为城市无访问权限错误：HTTP 403 且响应体含 AP010006。
  ///
  /// 依赖 [HttpCodeException.body]（DioManager 已透传非 2xx 响应体）。
  bool _isCityAccess(Exception e) {
    if (e is HttpCodeException && e.httpCode == 403) {
      return '${e.body}'.contains('AP010006');
    }
    return false;
  }

  Map<String, dynamic> _toStringKeyMap(Map<dynamic, dynamic> raw) =>
      raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
}

/// 心知 V3 请求基类：绝对 URL + 私钥 `key` 查询参数。
///
/// 心知为第三方域名，与 App 自身接口不同域；`url()` 直接返回绝对地址，
/// DioManager 对绝对地址会忽略其全局 baseUrl。
abstract class _SeniverseRequest extends HttpBaseRequest {
  /// 业务路径，如 `/weather/now.json`。
  String path();

  /// 业务参数（location、days 等）。
  Map<String, dynamic> bizParams();

  @override
  String url() => '${AppConfig.seniverseWeatherHostV3}${path()}';

  @override
  Map<String, dynamic> params() => <String, dynamic>{
        'key': AppConfig.seniverseV3KeyEffective,
        'language': 'zh-Hans',
        'unit': 'c',
        ...bizParams(),
      };
}

/// 实时天气 `/weather/now.json`。
class _WeatherNowRequest extends _SeniverseRequest {
  _WeatherNowRequest(this.location);

  final String location;

  @override
  String path() => '/weather/now.json';

  @override
  Map<String, dynamic> bizParams() => <String, dynamic>{'location': location};
}

/// 逐日预报 `/weather/daily.json`（取未来 4 天）。
class _WeatherDailyRequest extends _SeniverseRequest {
  _WeatherDailyRequest(this.location);

  final String location;

  @override
  String path() => '/weather/daily.json';

  @override
  Map<String, dynamic> bizParams() =>
      <String, dynamic>{'location': location, 'days': '4'};
}
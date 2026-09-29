import 'package:dio/dio.dart';
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';

/// 心知天气 V3 客户端：免费版数据接口，用私钥 `key` 鉴权。
///
/// 独立 Dio，避免与 App 自身接口的会话/重试逻辑纠缠。
/// 基址 [AppConfig.seniverseWeatherHostV3]（https://api.seniverse.com/v3）。
///
/// 注意：V3 免费版需在展示页注明数据来源；私钥走网络传输，安全性弱于 V4 公钥签名，
/// 后续若升级到 V4 数据产品再切回签名方案（原实现保留在 git 历史）。
class WeatherHttpClient {
  WeatherHttpClient._();

  /// 全局单例。
  static final WeatherHttpClient instance = WeatherHttpClient._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// 是否已配置 key（未配置时不发起请求）。
  bool get isConfigured => AppConfig.seniverseV3KeyEffective.isNotEmpty;

  /// 请求 V3 接口并返回整体 map。
  ///
  /// [path] 形如 `/weather/now.json`、`/weather/daily.json`，
  /// [params] 为业务参数（如 location、days）。language/unit 走默认值。
  Future<Map<String, dynamic>> get(String path, Map<String, dynamic> params) async {
    final Map<String, String> query = <String, String>{
      'key': AppConfig.seniverseV3KeyEffective,
      'language': 'zh-Hans',
      'unit': 'c',
    }..addAll(params.map((k, v) => MapEntry(k, '$v')));

    // 直接用绝对 URL 拼接，避开设 dio baseUrl 合并导致的路径丢失。
    final String url = Uri.parse('${AppConfig.seniverseWeatherHostV3}$path')
        .replace(queryParameters: query)
        .toString();

    try {
      final response = await _dio.get<dynamic>(url);
      final data = response.data;
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v));
      }
      throw StateError('心知天气返回格式异常: $data');
    } on DioException catch (e) {
      // 打印响应体，便于定位 401/403/quota 等根因。
      const LogService().error(
        '心知天气请求失败 $path | HTTP ${e.response?.statusCode} 响应: ${e.response?.data}',
      );
      rethrow;
    } on Exception catch (e, s) {
      const LogService().error('心知天气请求失败 $path', error: e, stackTrace: s);
      rethrow;
    }
  }
}
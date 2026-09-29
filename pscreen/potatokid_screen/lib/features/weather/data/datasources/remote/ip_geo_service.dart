import 'package:dio/dio.dart';
import 'package:potatokid_screen/app/hosts/app_hosts.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';

/// 记录一个经纬度位置。
typedef GeoLocation = ({double lat, double lon});

/// IP 反查定位：通过设备的公网 IP 反查近似经纬度（城市级，对天气足够）。
///
/// 电视盒子通常无 GPS，IP 反查无需权限即可拿到位置。
/// 依次尝试主备两个免费公开接口，全部失败返回 null。
class IpGeoService {
  IpGeoService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      ));

  final Dio _dio;

  /// 尝试从多个公开接口反查经纬度。
  Future<GeoLocation?> locate() async {
    for (final host in <String>[
      AppHosts.ipGeoPrimaryHost,
      AppHosts.ipGeoSecondaryHost,
    ]) {
      final GeoLocation? loc = await _tryHost(host);
      if (loc != null) return loc;
    }
    return null;
  }

  Future<GeoLocation?> _tryHost(String host) async {
    try {
      final response = await _dio.get<dynamic>(host);
      final data = response.data;
      if (data is Map) {
        final double? lat = _toNum(data['latitude']);
        final double? lon = _toNum(data['longitude']);
        if (lat != null && lon != null && (lat != 0 || lon != 0)) {
          return (lat: lat, lon: lon);
        }
      }
    } on Exception catch (e) {
      const LogService().warn('IP 反查失败: $host | $e');
    }
    return null;
  }

  double? _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
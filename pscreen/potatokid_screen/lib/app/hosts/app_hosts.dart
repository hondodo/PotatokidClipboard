import 'package:potatokid_screen/app/config/app_config.dart';

/// 域名/环境配置（来自 myStar 方案）
class AppHosts {
  const AppHosts._();

  static String baseHost = 'https://api.example.com';
  static String apiHost = 'https://api.example.com';
  static String h5Host = 'https://h5.example.com';

  /// 心知天气 V4 与 IP 反查（独立第三方域名，不参与 baseHost/切换逻辑）
  static String weatherHost = AppConfig.seniverseWeatherHost;
  static String ipGeoPrimaryHost = AppConfig.seniverseIpGeoHost;
  static String ipGeoSecondaryHost = AppConfig.seniverseIpGeoHostB;

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    baseHost = _toDioBaseUrl(AppConfig.baseUrl);
    apiHost = baseHost;
    _initialized = true;
  }

  static String _toDioBaseUrl(String host) {
    if (host.isEmpty) return host;
    if (host.startsWith('http://') || host.startsWith('https://')) return host;
    return 'https://$host';
  }
}

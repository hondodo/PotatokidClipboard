import 'package:potatokid_screen/app/config/app_config.dart';

/// 域名/环境配置（来自 myStar 方案）
class AppHosts {
  const AppHosts._();

  static String baseHost = 'https://api.example.com';
  static String apiHost = 'https://api.example.com';
  static String h5Host = 'https://h5.example.com';

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

import 'package:pscreen_screen/app/config/app_config.dart';

/// 域名/环境配置（来自 myStar 方案）
class AppHosts {
  const AppHosts._();

  /// 心知天气 V4 与 IP 反查（独立第三方域名，不参与 baseHost/切换逻辑）
  static String weatherHost = AppConfig.seniverseWeatherHost;
  static String ipGeoPrimaryHost = AppConfig.seniverseIpGeoHost;
  static String ipGeoSecondaryHost = AppConfig.seniverseIpGeoHostB;
}

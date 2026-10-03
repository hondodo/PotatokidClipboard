import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 AppConfig.initialize() 后使用。
class AppConfig {
  const AppConfig._();

  static String baseUrl = 'https://api.example.com';
  static bool isDebug = true;
  static bool enableProxy = false;
  static bool enableDevTools = true;

  /// 心知天气 V3（免费版）：key 私钥鉴权
  static String seniverseV3Key = '';
  static String seniverseWeatherHostV3 = 'https://api.seniverse.com/v3';

  /// IP 反查城市不受免费版覆盖（AP010006）时的默认回退城市。
  static String seniverseDefaultLocation = '湛江';

  /// 心知天气 V4（公钥签名验证，需购买 V4 数据产品权限）
  static String seniversePublicKey = '';
  static String seniverseSecretKey = '';
  static String seniverseWeatherHost = 'https://api.seniverse.com/v4';
  static String seniverseIpGeoHost = 'https://ipwho.is/';
  static String seniverseIpGeoHostB = 'https://ipapi.co/json/';

  /// 「我的」页「天气城市」可选列表（不含「自动」——自动即空值，为隐式首项）。
  ///
  /// 实际取值由 DataFiles 决定（`weather_cities.txt`：git 同步结果 → 本地缓存 →
  /// 包内 assets 默认），`.env` 的 `WEATHER_CITIES` 仅作兼容兜底。
  static List<String> weatherCities = const <String>[];

  /// 频道列表优先顺序（`tv_name_order.txt`）。
  ///
  /// 命中的频道按此处的先后顺序置顶，未列出的保持原顺序排在其后。
  /// 取值来源同 [weatherCities]（`.env` 的 `TV_NAME_ORDER` 仅作兜底）。
  static List<String> tvNameOrder = const <String>[];

  /// 需要排除的频道名（`tv_name_hide.txt`）。
  ///
  /// 取值来源同 [weatherCities]（`.env` 的 `TV_NAME_HIDE` 仅作兜底）。
  static List<String> tvNameHide = const <String>[];

  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // 已初始化或资源缺失时忽略，后续读取使用 fallback
    }
    baseUrl = _readString('BASE_URL', baseUrl);
    isDebug = _readBool('IS_DEBUG', isDebug);
    enableProxy = _readBool('ENABLE_PROXY', enableProxy);
    enableDevTools = _readBool('ENABLE_DEV_TOOLS', enableDevTools);

    seniverseV3Key = _readString('SENIVERSE_V3_KEY', seniverseV3Key);
    seniverseWeatherHostV3 = _readString('SENIVERSE_WEATHER_HOST_V3', seniverseWeatherHostV3);
    seniverseDefaultLocation = _readString('SENIVERSE_DEFAULT_LOCATION', seniverseDefaultLocation);
    seniversePublicKey = _readString('SENIVERSE_PUBLIC_KEY', seniversePublicKey);
    seniverseSecretKey = _readString('SENIVERSE_SECRET_KEY', seniverseSecretKey);
    seniverseWeatherHost = _readString('SENIVERSE_WEATHER_HOST', seniverseWeatherHost);
    seniverseIpGeoHost = _readString('SENIVERSE_IP_GEO_HOST', seniverseIpGeoHost);
    seniverseIpGeoHostB = _readString('SENIVERSE_IP_GEO_HOST_B', seniverseIpGeoHostB);

    weatherCities = _readStringList('WEATHER_CITIES', weatherCities);

    tvNameOrder = _readStringList('TV_NAME_ORDER', tvNameOrder);
    tvNameHide = _readStringList('TV_NAME_HIDE', tvNameHide);
  }

  /// V3 请求用的 key：优先取显式配置的 V3 key，否则回退到私钥（二者常为同一值）。
  static String get seniverseV3KeyEffective => seniverseV3Key.isNotEmpty ? seniverseV3Key : seniverseSecretKey;

  static String _readString(String key, String fallback) {
    try {
      return dotenv.maybeGet(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static bool _readBool(String key, bool fallback) => _readString(key, fallback.toString()).toLowerCase() == 'true';

  /// 读取逗号分隔的字符串列表；空值/全空白时返回 [fallback]。
  static List<String> _readStringList(String key, List<String> fallback) {
    final String raw = _readString(key, '');
    if (raw.trim().isEmpty) return fallback;
    final List<String> items = raw.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
    return items.isEmpty ? fallback : items;
  }
}

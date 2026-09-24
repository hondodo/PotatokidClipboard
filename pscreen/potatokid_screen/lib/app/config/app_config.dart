import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 AppConfig.initialize() 后使用。
class AppConfig {
  const AppConfig._();

  static String baseUrl = 'https://api.example.com';
  static bool isDebug = true;
  static bool enableProxy = false;
  static bool enableDevTools = true;

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
  }

  static String _readString(String key, String fallback) {
    try {
      return dotenv.maybeGet(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static bool _readBool(String key, bool fallback) =>
      _readString(key, fallback.toString()).toLowerCase() == 'true';
}

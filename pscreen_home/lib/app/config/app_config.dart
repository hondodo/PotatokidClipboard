import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 AppConfig.initialize() 后使用。
///
/// .env 键：
/// - AS_HOST：Home Assistant 地址（如 http://192.168.1.10:8123）
/// - AS_KEY ：长期访问令牌（HA 个人资料 → 安全 → 长期访问令牌）
class AppConfig {
  const AppConfig._();

  static String haHost = 'http://localhost:8123';
  static String haToken = '';

  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // 已初始化或资源缺失时忽略，后续读取使用 fallback
    }
    haHost = _readString('AS_HOST', haHost).trim();
    haToken = _readString('AS_KEY', haToken).trim();
  }

  /// 是否已配置可用的连接信息
  static bool get isConfigured => haHost.isNotEmpty && haToken.isNotEmpty;

  /// Home Assistant WebSocket 地址（http→ws、https→wss，去掉尾部斜杠）
  static String get haWsUrl {
    var base = haHost;
    if (base.startsWith('https://')) {
      base = 'wss://${base.substring('https://'.length)}';
    } else if (base.startsWith('http://')) {
      base = 'ws://${base.substring('http://'.length)}';
    } else if (!base.startsWith('ws')) {
      base = 'ws://$base';
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/api/websocket';
  }

  static String _readString(String key, String fallback) {
    try {
      return dotenv.maybeGet(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }
}

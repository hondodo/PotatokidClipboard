import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 AppConfig.initialize() 后使用。
///
/// 连接信息分两层，**生效优先级：持久化覆盖 > .env 默认值**：
/// - `.env` 键 `AS_HOST` / `AS_KEY`：部署默认值（见 [envHost] / [envToken]）；
/// - 设置页手动输入：经 `SettingsStore` 持久化，
///   启动时由 main() 调用 [applyOverrides] 注入（见 [haHost] / [haToken]）；
///   清空保存即删除覆盖，回落 .env。
///
/// 覆盖值存 **host 原始地址**（如 `192.168.1.10:8123`），
/// 转 ws 协议在 [haWsUrl] 统一处理。
class AppConfig {
  const AppConfig._();

  /// .env 默认地址（AS_HOST），无覆盖时的生效值
  static String envHost = 'http://localhost:8123';

  /// .env 默认令牌（AS_KEY），无覆盖时的生效值
  static String envToken = '';

  /// 持久化覆盖：非空时优先生效（启动时由 applyOverrides 注入）
  static String _hostOverride = '';
  static String _tokenOverride = '';

  /// 生效的 Home Assistant 地址（覆盖 > .env）
  static String get haHost =>
      _hostOverride.isNotEmpty ? _hostOverride : envHost;

  /// 生效的访问令牌（覆盖 > .env）
  static String get haToken =>
      _tokenOverride.isNotEmpty ? _tokenOverride : envToken;

  /// 是否存在手动设置的地址 / 令牌覆盖
  static bool get hasHostOverride => _hostOverride.isNotEmpty;
  static bool get hasTokenOverride => _tokenOverride.isNotEmpty;

  /// 注入持久化的覆盖值（main() 启动时调用一次；空 = 无覆盖）
  static void applyOverrides({String host = '', String token = ''}) {
    _hostOverride = host.trim();
    _tokenOverride = token.trim();
  }

  /// 读取 .env 默认值（main() 中最先调用）
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // 已初始化或资源缺失时忽略，后续读取使用 fallback
    }
    envHost = _readString('AS_HOST', envHost).trim();
    envToken = _readString('AS_KEY', envToken).trim();
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

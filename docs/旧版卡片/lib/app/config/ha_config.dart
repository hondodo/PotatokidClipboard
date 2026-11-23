import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 HaConfig.initialize() 后使用。
///
/// 连接信息分两层，**生效优先级：持久化覆盖 > .env 默认值**：
/// - `.env` 键 `AS_HOST` / `AS_KEY`：部署默认值（见 [envHost] / [envToken]）；
/// - 设置页手动输入：经 `SettingsStore` 持久化，
///   启动时由 main() 调用 [applyOverrides] 注入（见 [haHost] / [haToken]）；
///   清空保存即删除覆盖，回落 .env。
///
/// 覆盖值存 **host 原始地址**（如 `192.168.1.10:8123`），
/// 转 ws 协议在 [haWsUrl] 统一处理。
class HaConfig {
  const HaConfig._();

  /// .env 默认地址（AS_HOST），无覆盖时的生效值
  static String envHost = 'http://localhost:8123';

  /// .env 默认令牌（AS_KEY），无覆盖时的生效值
  static String envToken = '';

  /// .env 指定只显示的家庭名（HONE_MANE，兼容 HOME_NAME）。
  /// 留空或「全部」表示不限制，由用户在主页选择家庭。
  static String envHomeName = '';

  /// .env 默认的管理服务端地址（如 `http://192.168.31.2:3000`）。
  /// 留空表示不启用家庭配置 / 布局同步。
  static String envServerBaseUrl = '';

  /// 服务端下发的家庭白名单：null = 未配置（回落 .env），
  /// 空列表 = 不限制（全部），非空 = 只允许这些家庭。
  static List<String>? _serverHomes;

  /// 服务端下发的配置来源 / 归属（仅用于展示与排查）。
  static String serverHomeSource = '';
  static String serverOwner = '';
  static String serverLayoutKey = '';

  /// 生效的家庭白名单（空列表表示「全部」）。
  static List<String> get visibleHomes {
    final List<String>? serverHomes = _serverHomes;
    if (serverHomes != null) {
      return List<String>.unmodifiable(serverHomes);
    }
    final String name = envHomeName.trim();
    if (name.isEmpty) return const <String>[];
    if (name == '全部' || name.toLowerCase() == 'all') return const <String>[];
    return <String>[name];
  }

  /// 生效的固定家庭名：仅当只允许 1 个家庭时非空。
  ///
  /// 指定后主页只显示该家庭的数据，并隐藏家庭概览条
  /// （概览条里的「全部」按钮会解除筛选，与固定家庭冲突）。
  static String get pinnedHomeName {
    final List<String> homes = visibleHomes;
    return homes.length == 1 ? homes.first : '';
  }

  /// 是否锁定家庭（只允许 1 个家庭，或 .env 指定了单个家庭）。
  static bool get isHomeLocked => visibleHomes.length == 1;

  /// 注入服务端下发的家庭配置（启动注册 / 心跳时调用）。
  static void applyServerConfig({
    List<String>? homes,
    String source = '',
    String owner = '',
    String layoutKey = '',
  }) {
    _serverHomes = homes == null
        ? null
        : List<String>.unmodifiable(homes);
    serverHomeSource = source;
    serverOwner = owner;
    serverLayoutKey = layoutKey;
  }

  /// 清除服务端配置（测试 / 调试用）。
  static void clearServerConfig() {
    _serverHomes = null;
    serverHomeSource = '';
    serverOwner = '';
    serverLayoutKey = '';
  }

  /// 持久化覆盖：非空时优先生效（启动时由 applyOverrides 注入）
  static String _hostOverride = '';
  static String _tokenOverride = '';
  static String _serverBaseUrlOverride = '';

  /// 生效的 Home Assistant 地址（覆盖 > .env）
  static String get haHost =>
      _hostOverride.isNotEmpty ? _hostOverride : envHost;

  /// 生效的访问令牌（覆盖 > .env）
  static String get haToken =>
      _tokenOverride.isNotEmpty ? _tokenOverride : envToken;

  /// 生效的管理服务端地址（覆盖 > .env）
  static String get serverBaseUrl {
    final String value = _serverBaseUrlOverride.isNotEmpty
        ? _serverBaseUrlOverride
        : envServerBaseUrl;
    String base = value.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /// 是否存在手动设置的地址 / 令牌覆盖
  static bool get hasHostOverride => _hostOverride.isNotEmpty;
  static bool get hasTokenOverride => _tokenOverride.isNotEmpty;
  static bool get hasServerBaseUrlOverride => _serverBaseUrlOverride.isNotEmpty;

  /// 注入持久化的覆盖值（main() 启动时调用一次；空 = 无覆盖）
  static void applyOverrides({
    String host = '',
    String token = '',
    String serverBaseUrl = '',
  }) {
    _hostOverride = host.trim();
    _tokenOverride = token.trim();
    _serverBaseUrlOverride = serverBaseUrl.trim();
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
    envServerBaseUrl = _readString('SERVER_BASE_URL', '').trim();
    // 历史键名 HONE_MANE（.env_example 一直这么写）优先；
    // 同时兼容拼写正确的 HOME_NAME。
    envHomeName = _readString('HONE_MANE', _readString('HOME_NAME', '')).trim();
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

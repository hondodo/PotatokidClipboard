import 'package:package_info_plus/package_info_plus.dart';

/// ws 握手上报的客户端标识：app（包名）/ version（如 1.0.0）/ build（如 2）。
///
/// 服务端在线日志与 realtime.html 据此区分不同控制端（按 app + build
/// 显示不同形态）。首次读取后缓存；平台通道失败（如单测环境）时全部
/// 为空字符串，服务端对空值同样兼容。
class ClientInfo {
  const ClientInfo({this.app = '', this.version = '', this.build = ''});

  /// 包名（如 `com.potatokid.pscreen_home`）。
  final String app;

  /// 语义化版本号（pubspec `version:` 的 `+` 前半段）。
  final String version;

  /// 构建号（pubspec `version:` 的 `+` 后半段）。
  final String build;

  static Future<ClientInfo>? _pending;

  /// 进程内单例：首次读取后复用（[PackageInfo.fromPlatform] 走平台通道）。
  static Future<ClientInfo> current() => _pending ??= _load();

  static Future<ClientInfo> _load() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return ClientInfo(
        app: info.packageName.trim(),
        version: info.version.trim(),
        build: info.buildNumber.trim(),
      );
    } catch (_) {
      return const ClientInfo();
    }
  }
}

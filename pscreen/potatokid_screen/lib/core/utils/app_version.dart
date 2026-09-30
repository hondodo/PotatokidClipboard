import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本信息（设置页「版本」行展示）。
///
/// 用 [PackageInfo.fromPlatform] 读取平台实际打包的版本号，**无需手工维护**：
/// 值直接来自 `pubspec.yaml` 的 `version:`（Android 侧为 versionName + versionCode），
/// 发版时只改 pubspec 即可。
///
/// 通过 DI 注册为单例，在 `Injection.init()` 时读取一次（启动阶段），
/// 页面直接读取缓存字符串，避免每帧走平台通道，也没有加载态闪烁。
class AppVersion {
  AppVersion._();

  /// 读取失败时的占位文案（如平台通道异常），保证界面不崩。
  static const String fallback = 'v—';

  String _display = fallback;

  /// 读取平台版本号并构造实例（启动阶段调用一次，失败则用 [fallback]）。
  static Future<AppVersion> load() async {
    final AppVersion info = AppVersion._();
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String version = packageInfo.version.trim();
      final String build = packageInfo.buildNumber.trim();
      if (version.isNotEmpty) {
        info._display = build.isEmpty ? 'v$version' : 'v$version+$build';
      }
    } catch (_) {
      // 读取失败保留占位文案，不影响其它功能。
    }
    return info;
  }

  /// 展示文案：`v1.0.0+1`（读取失败时为 [fallback]）。
  String get display => _display;
}

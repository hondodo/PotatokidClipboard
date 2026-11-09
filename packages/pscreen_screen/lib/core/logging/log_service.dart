import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/config/app_config.dart';

/// 统一日志服务，通过 DI 注入使用：`ScreenInjection.get<LogService>()`
class LogService {
  const LogService();

  /// 是否输出 info 日志：调试构建，或 `.env` 显式打开 `IS_DEBUG=true`。
  ///
  /// release 包现场排障（电视盒子无法连调试器）依赖它：默认 `.env` 就是 true，
  /// 需要安静时在 `.env` 改成 false 重打包即可。
  static bool get _verbose => kDebugMode || AppConfig.isDebug;

  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  void info(String message) {
    if (_verbose) {
      debugPrint('[INFO][${DateTime.now()}] $message');
    }
  }

  void warn(String message) {
    debugPrint('[WARN] $message');
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[ERROR] $message${error == null ? '' : ' | $error'}');
    if (kDebugMode && stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}

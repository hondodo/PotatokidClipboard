import 'package:flutter/foundation.dart';

/// 统一日志服务，通过 DI 注入使用：`Injection.get<LogService>()`
class LogService {
  const LogService();

  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  void info(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
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

import 'package:flutter/foundation.dart';

/// 简易日志（仅 debugPrint）。
class AppLog {
  const AppLog._();

  static void d(String message) => debugPrint('[AppLog] $message');
  static void i(String message) => debugPrint('[AppLog] $message');
  static void e(String message) => debugPrint('[AppLog][E] $message');
}

import 'package:flutter/foundation.dart';

/// 简易日志（仅 debugPrint）。
class ControlLog {
  const ControlLog._();

  static void d(String message) => debugPrint('[ControlLog] $message');
  static void i(String message) => debugPrint('[ControlLog] $message');
  static void e(String message) => debugPrint('[ControlLog][E] $message');
}

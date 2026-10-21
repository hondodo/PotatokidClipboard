// ignore_for_file: avoid_print
import 'package:pscreen_screen/core/di/screen_injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

class Log {
  static void d(String message) {
    try {
      ScreenInjection.get<LogService>().debug(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void i(String message) {
    try {
      ScreenInjection.get<LogService>().info(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void warn(String message) {
    try {
      ScreenInjection.get<LogService>().debug(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    try {
      ScreenInjection.get<LogService>().error(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void startEndD(String message, Function execFun) {
    Log.d('[START] $message');
    execFun();
    Log.d('[END] $message');
  }
}

// ignore_for_file: avoid_print
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';

class Log {
  static void d(String message) {
    try {
      Injection.get<LogService>().debug(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void i(String message) {
    try {
      Injection.get<LogService>().info(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void warn(String message) {
    try {
      Injection.get<LogService>().debug(message);
    } catch (e) {
      print('[AppLog] log debug error: $e');
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    try {
      Injection.get<LogService>().error(message);
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

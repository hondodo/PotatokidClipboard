import 'package:logger/logger.dart';

class Log {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      printEmojis: false,
      noBoxingByDefault: true,
    ),
    output: MultiOutput([
      ConsoleOutput(),
    ]),
  );

  static void e(String message) {
    // print('[Log][${DateTime.now().toIso8601String()}] error: $message');
    _logger.e(message);
  }

  static void d(String message) {
    // debugPrint('[Log][${DateTime.now().toIso8601String()}] debug: $message');
    _logger.d(message);
  }

  static void i(String message) {
    // debugPrint('[Log][${DateTime.now().toIso8601String()}] info: $message');
    _logger.i(message);
  }

  static void w(String message) {
    // debugPrint('[Log][${DateTime.now().toIso8601String()}] warning: $message');
    _logger.w(message);
  }
}

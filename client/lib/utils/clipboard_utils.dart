import 'package:flutter/services.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

class ClipboardUtils {
  static const int _maxAttempts = 5;
  static Future<bool> _writeQueue = Future<bool>.value(true);

  ClipboardUtils._();

  static Future<bool> setText(String text) {
    final operation = _writeQueue.then((_) => _setTextWithRetry(text));
    _writeQueue = operation;
    return operation;
  }

  static Future<bool> _setTextWithRetry(String text) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        return true;
      } on PlatformException catch (error) {
        final isClipboardBusy =
            error.code == 'Clipboard error' && error.details?.toString() == '5';
        if (!isClipboardBusy || attempt == _maxAttempts) {
          Log.e('ClipboardUtils] 设置剪贴板失败: $error');
          return false;
        }
        await Future<void>.delayed(Duration(milliseconds: attempt * 50));
      } catch (error) {
        Log.e('ClipboardUtils] 设置剪贴板失败: $error');
        return false;
      }
    }
    return false;
  }
}

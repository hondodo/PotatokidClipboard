import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/nim_manager.dart';

/// nim_core_v2 仅提供 Android/iOS/macOS/Windows/Web 实现（无 Linux 包）。
///
/// 在不支持的平台上，`init` 必须在读取 `late options` 字段之前就返回，
/// 否则会抛 `LateInitializationError: Field 'options' has not been initialized`。
bool get _platformSupported =>
    kIsWeb ||
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isWindows;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NimManager.init：无 NIM 实现的平台（如 Linux）返回 false，不抛 LateError', () async {
    // 仅在真正不支持的平台上有意义（支持的平台会去初始化真实 SDK，测试环境跑不了）。
    if (_platformSupported) return;

    final bool ok = await NimManager().init(appKey: 'test-app-key');
    expect(ok, isFalse, reason: '不支持的平台应跳过初始化并返回 false');
  });
}

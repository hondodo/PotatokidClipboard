import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/device/device_identity.dart';

void main() {
  test('桌面端 model() 读本机真机型，不走 Android 原生通道', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final String model = await DeviceIdentity.model();
    // ignore: avoid_print
    print('[DeviceIdentity.model] 本机采集结果: "$model"');

    expect(model.contains('Android TV'), isFalse);
    expect(model.length, lessThanOrEqualTo(64));
    // Windows 开发机应能读到 BIOS 机型；其它平台不强制（避免 CI 环境差异）。
    if (Platform.isWindows) expect(model, isNotEmpty);
  });
}

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备身份：用于服务端识别「同一台中控屏」。
///
/// 优先读取 Android 的 `Settings.Secure.ANDROID_ID`（卸载重装不变），
/// 通过宿主 `MainActivity` 的 `potatokid/volume` 通道获取；
/// 非 Android / 取不到时退回本地持久化的随机 ID（卸载后会变，
/// 但至少桌面端调试可用）。
class DeviceIdentity {
  const DeviceIdentity._();

  static const MethodChannel _channel = MethodChannel('potatokid/volume');
  static const String _prefsKey = 'device_identity_v1';

  static String _deviceId = '';
  static String _model = '';

  /// 稳定设备 ID（带 `android_` / `gen_` 前缀，便于服务端区分来源）。
  static Future<String> deviceId() async {
    if (_deviceId.isNotEmpty) return _deviceId;
    try {
      final String? androidId =
          await _channel.invokeMethod<String>('getAndroidId');
      final String value = (androidId ?? '').trim();
      if (value.isNotEmpty) {
        _deviceId = 'android_$value';
        return _deviceId;
      }
    } catch (_) {
      // 非 Android 平台没有该通道，走本地随机 ID。
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString(_prefsKey);
    if (stored == null || stored.isEmpty) {
      stored = 'gen_${_randomHex(16)}';
      await prefs.setString(_prefsKey, stored);
    }
    _deviceId = stored;
    return _deviceId;
  }

  /// 设备型号（用于 Admin 列表展示，取不到时返回空串）。
  static Future<String> model() async {
    if (_model.isNotEmpty) return _model;
    try {
      final String? value =
          await _channel.invokeMethod<String>('getDeviceModel');
      _model = (value ?? '').trim();
    } catch (_) {
      _model = '';
    }
    return _model;
  }

  static String _randomHex(int bytes) {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

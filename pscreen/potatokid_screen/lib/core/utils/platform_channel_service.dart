import 'package:flutter/services.dart';

/// 系统音量/设备型号通道（Android MethodChannel）。
class PlatformChannelService {
  PlatformChannelService._();

  static final PlatformChannelService instance = PlatformChannelService._();

  static const MethodChannel _channel = MethodChannel('potatokid/volume');

  Future<void> volumeUp() async {
    try {
      await _channel.invokeMethod<void>('volumeUp');
    } catch (e) {
      // 忽略
    }
  }

  Future<void> volumeDown() async {
    try {
      await _channel.invokeMethod<void>('volumeDown');
    } catch (e) {
      // 忽略
    }
  }

  Future<void> toggleMute() async {
    try {
      await _channel.invokeMethod<void>('toggleMute');
    } catch (e) {
      // 忽略
    }
  }

  Future<String> deviceModel() async {
    try {
      final String? model = await _channel.invokeMethod<String>('getDeviceModel');
      if (model != null && model.isNotEmpty) return model;
    } catch (e) {
      // 忽略
    }
    return 'Android TV';
  }
}

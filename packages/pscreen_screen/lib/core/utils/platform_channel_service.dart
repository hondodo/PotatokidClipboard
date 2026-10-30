import 'package:flutter/services.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart'
    show VolumeControl;

/// 系统音量/设备型号通道（Android MethodChannel）。
class PlatformChannelService implements VolumeControl {
  PlatformChannelService._();

  static final PlatformChannelService instance = PlatformChannelService._();

  static const MethodChannel _channel = MethodChannel('potatokid/volume');

  @override
  Future<void> volumeUp() async {
    try {
      await _channel.invokeMethod<void>('volumeUp');
    } catch (e) {
      // 忽略
    }
  }

  @override
  Future<void> volumeDown() async {
    try {
      await _channel.invokeMethod<void>('volumeDown');
    } catch (e) {
      // 忽略
    }
  }

  @override
  Future<void> toggleMute() async {
    try {
      await _channel.invokeMethod<void>('toggleMute');
    } catch (e) {
      // 忽略
    }
  }

  /// 当前媒体音量（0-100 百分比）；取不到（非 Android / 原生未实现）返回 null。
  Future<int?> getVolume() async {
    try {
      final int? volume = await _channel.invokeMethod<int>('getVolume');
      if (volume != null) return volume.clamp(0, 100);
    } catch (e) {
      // 忽略
    }
    return null;
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

  /// 设备唯一编号**原始值**：`androidId`（API 26+ 由「签名密钥+用户+设备」决定，
  /// 卸载重装不变；API 26 以下为设备级值，同样跨卸载存活）、`mediaDrmId`
  /// （Widevine 设备唯一 ID，androidId 不可用时兜底）。两者都可能为空串。
  ///
  /// 只负责取原始值，归一化与格式化见 `DeviceIdentity`。
  Future<({String androidId, String mediaDrmId})> deviceIdentity() async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('getDeviceIdentity');
      if (raw != null) {
        return (
          androidId: '${raw['androidId'] ?? ''}',
          mediaDrmId: '${raw['mediaDrmId'] ?? ''}',
        );
      }
    } catch (e) {
      // 忽略：非 Android 平台或原生异常
    }
    return (androidId: '', mediaDrmId: '');
  }
}

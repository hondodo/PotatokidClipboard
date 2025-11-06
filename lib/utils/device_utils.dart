import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';

class DeviceUtils {
  static final DeviceUtils _instance = DeviceUtils._();
  DeviceUtils._();
  static DeviceUtils get instance => _instance;

  String deviceId = '';

  Future<void> updateDeviceId() async {
    try {
      // 尝试使用 flutter_udid 获取设备 ID
      String udid = await FlutterUdid.udid;
      udid = udid.replaceAll('-', '');
      deviceId = udid;
    } catch (e) {
      // 如果 flutter_udid 失败（例如 Windows 上的 wmic 命令不可用），使用备用方案
      debugPrint('flutter_udid failed: $e, using fallback method');
      deviceId = await _getFallbackDeviceId();
    }
  }

  /// 备用方案：使用 device_info_plus 获取设备信息并生成设备 ID
  Future<String> _getFallbackDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isWindows) {
        final WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
        // 使用计算机名、用户名和产品名称生成唯一 ID
        final String uniqueString =
            '${windowsInfo.computerName}_${windowsInfo.userName}_${windowsInfo.productName}';
        final bytes = utf8.encode(uniqueString);
        final digest = sha256.convert(bytes);
        return digest.toString();
      } else if (Platform.isLinux) {
        final LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        // 使用机器 ID 和主机名
        final String uniqueString =
            '${linuxInfo.machineId}_${linuxInfo.prettyName}_${linuxInfo.version}';
        final bytes = utf8.encode(uniqueString);
        final digest = sha256.convert(bytes);
        return digest.toString();
      } else if (Platform.isMacOS) {
        final MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        // 使用主机名和计算机名
        final String uniqueString =
            '${macInfo.hostName}_${macInfo.computerName}_${macInfo.model}';
        final bytes = utf8.encode(uniqueString);
        final digest = sha256.convert(bytes);
        return digest.toString();
      } else if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // 使用 Android ID（如果可用）
        return androidInfo.id.replaceAll('-', '');
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        // 使用 identifierForVendor
        return iosInfo.identifierForVendor?.replaceAll('-', '') ??
            'ios_${iosInfo.name}_${iosInfo.systemVersion}'.replaceAll('-', '');
      }

      // 默认情况：生成随机 ID
      return 'device_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Fallback device ID generation failed: $e');
      // 最后的备用方案：使用时间戳
      return 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  OsType get osType {
    if (Platform.isIOS) {
      return OsType.ios;
    } else if (Platform.isAndroid) {
      return OsType.android;
    } else if (Platform.isWindows) {
      return OsType.windows;
    } else if (Platform.isLinux) {
      return OsType.linux;
    } else if (Platform.isMacOS) {
      return OsType.macos;
    } else {
      return OsType.unknown;
    }
  }
}

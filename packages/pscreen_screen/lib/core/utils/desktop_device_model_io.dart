import 'dart:io' show File, Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:pscreen_screen/core/utils/desktop_device_model_format.dart';
import 'package:win32_registry/win32_registry.dart';

/// 桌面端设备型号：优先真实硬件机型，拿不到时回落操作系统名称。
///
/// 全部为进程内读取，**不调用 `Process.run`**：
/// - Windows：`HKLM\HARDWARE\DESCRIPTION\System\BIOS` 的
///   `SystemManufacturer` / `SystemProductName`（Win32 注册表 API）；
/// - Ubuntu：`/sys/class/dmi/id/sys_vendor` + `product_name`（普通用户可读）；
/// - 兜底：`device_info_plus` 的 `productName` / `prettyName`，
///   再退化为 `Platform.operatingSystemVersion`。
///
/// 任何一步失败都不抛出，返回空串即可（服务端会保留既有型号）。
Future<String> desktopDeviceModel() async {
  if (Platform.isWindows) return _windowsModel();
  if (Platform.isLinux) return _linuxModel();
  if (Platform.isMacOS) return _macOsModel();
  // Android / iOS 由各自的原生通道负责，桌面采集不参与。
  return '';
}

Future<String> _windowsModel() async {
  String? manufacturer;
  String? product;
  try {
    // win32_registry 3.x：预定义根键 + open/getString（进程内 Win32 API）。
    final key = LOCAL_MACHINE.open(r'HARDWARE\DESCRIPTION\System\BIOS');
    try {
      manufacturer = key.getString('SystemManufacturer');
      product = key.getString('SystemProductName');
    } finally {
      key.close();
    }
  } catch (_) {
    // 注册表被策略限制 / 非真 Windows 环境：继续用 OS 信息兜底。
  }

  String? osName;
  try {
    final WindowsDeviceInfo info = await DeviceInfoPlugin().windowsInfo;
    osName = <String>[info.productName, info.displayVersion]
        .where((String part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
  } catch (_) {
    // 插件未注册（如纯 Dart 测试环境）：用 Platform 自带版本兜底。
  }

  return formatDesktopModel(
    manufacturer: manufacturer,
    product: product,
    osName: osName,
    fallback: Platform.operatingSystemVersion,
  );
}

Future<String> _linuxModel() async {
  String? osName;
  try {
    osName = (await DeviceInfoPlugin().linuxInfo).prettyName;
  } catch (_) {
    // /etc/os-release 缺失或插件未注册时忽略。
  }
  return formatDesktopModel(
    manufacturer: _readSysfs('sys_vendor'),
    product: _readSysfs('product_name'),
    osName: osName,
    fallback: Platform.operatingSystemVersion,
  );
}

Future<String> _macOsModel() async {
  try {
    final String model = (await DeviceInfoPlugin().macOsInfo).model;
    return formatDesktopModel(
      product: model,
      fallback: Platform.operatingSystemVersion,
    );
  } catch (_) {
    return formatDesktopModel(fallback: Platform.operatingSystemVersion);
  }
}

/// DMI 文件是几百字节的小文本，同步读取即可；无权限 / 容器环境返回 null。
String? _readSysfs(String name) {
  try {
    return File('/sys/class/dmi/id/$name').readAsStringSync().trim();
  } catch (_) {
    return null;
  }
}

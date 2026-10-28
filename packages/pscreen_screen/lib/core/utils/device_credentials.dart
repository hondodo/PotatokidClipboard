import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_identity.dart';

/// 设备凭据：HTTP（ptools 登录）与实时网关（ws 上报）共用同一组「账号 + 口令」。
///
/// 服务端以 `datas/register/users/<账号>`（内容为口令 MD5）为唯一校验源，
/// 故两条链路必须提交完全相同的凭据。
///
/// 取值优先级（账号与口令各自独立）：
/// 1. 设置页自定义值（[AppSettings.remoteAccount] / [AppSettings.remotePassword]）
/// 2. `.env` 兜底（`TOOLS_TOKEN` / `TOOLS_PASSWORD`，未配置时为空）
/// 3. 默认值：账号 = 设备号（16 位 hex，无连字符）、口令 = `123456`
class DeviceCredentials {
  const DeviceCredentials._();

  /// 默认口令（与服务端自动建档口令一致，见服务端 accounts.js）。
  static const String defaultPassword = '123456';

  /// 生效账号：自定义 > `.env` > 16 位 hex 设备号。
  static Future<String> account() async {
    final String custom = AppSettings.instance.remoteAccount.trim();
    if (custom.isNotEmpty) return custom;
    final String fallback = AppConfig.toolsToken.trim();
    if (fallback.isNotEmpty) return fallback;
    return deviceId();
  }

  /// 生效口令：自定义 > `.env` > 默认 `123456`。
  static String password() {
    final String custom = AppSettings.instance.remotePassword.trim();
    if (custom.isNotEmpty) return custom;
    final String fallback = AppConfig.toolsPassword.trim();
    if (fallback.isNotEmpty) return fallback;
    return defaultPassword;
  }

  /// 口令 MD5——HTTP 登录与 ws 握手提交的同一个值。
  static String passwordMd5() =>
      md5.convert(utf8.encode(password())).toString();

  /// 设备号（`xxxx-xxxx-xxxx-xxxx` 去掉连字符的 16 位 hex）；解析失败返回空串。
  static Future<String> deviceId() async {
    try {
      final String id = await DeviceIdentity.instance.resolve();
      return id.replaceAll('-', '');
    } catch (_) {
      // 平台通道不可用（测试/桌面端）：无设备号可上报，返回空串。
      return '';
    }
  }
}

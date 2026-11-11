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
/// 账号恒定 = `<flavor>.<kind>.<设备号16hex>`：
/// - `flavor`、`kind` 由宿主启动时通过 [configureAccountScope] 传入
///   （取自构建 flavor 与 `kindOfApp()` 的实际 kind，不在此处维护映射表）；
/// - 设备号取 [DeviceIdentity] 解析结果的 16 位 hex（去掉连字符）。
///
/// 默认不允许手动改账号 / 口令；仅当 `.env` 的 `ENABLE_CHANGE_ACCOUNT=true`
/// 时（调试包）才按「自定义 > `.env` > 派生值/默认口令」取值。
///
/// **家长端例外（claim 闸门）**：只有 parent flavor 显式调用
/// [configureClaimEnabled(true)] 后，[account] 才会优先返回已 claim 的自定义
/// 登录名。闸门默认关闭，中控端 / TV 端走的是与改动前逐字相同的分支，
/// 登录链路不受影响。
class DeviceCredentials {
  const DeviceCredentials._();

  /// 默认口令（与服务端自动建档口令一致，见服务端 accounts.js）。
  static const String defaultPassword = '123456';

  /// 账号作用域 `<flavor>.<kind>`；由宿主启动时设置。
  static String _accountScope = '';

  /// 是否允许使用家长自定义登录名；默认关闭，由 parent flavor 显式开启。
  static bool _claimEnabled = false;

  /// 宿主启动时设置账号作用域（如 `tv.tv`、`board.home`、`parent.parent`）。
  static void configureAccountScope(String scope) {
    _accountScope = scope.trim();
  }

  /// 是否允许 [account] 使用已 claim 的自定义登录名。
  ///
  /// 只有 parent flavor 传 true；其它宿主不调用（或传 false）时，
  /// [account] / [enforceDerivedAccount] 的行为与历史版本完全一致。
  static void configureClaimEnabled(bool enabled) {
    _claimEnabled = enabled;
  }

  /// 派生账号；设备号不可用时返回空串，而不是仅返回作用域。
  static Future<String> derivedAccount() async {
    final String id = await deviceId();
    if (id.isEmpty || _accountScope.isEmpty) return '';
    return '$_accountScope.$id';
  }

  /// 生效账号：claim 闸门开启且已设置自定义登录名时优先返回它；
  /// 其余情况沿用原优先级（调试自定义 > `.env` > 派生值）。
  static Future<String> account() async {
    if (_claimEnabled) {
      await AppSettings.instance.ensureLoaded();
      final String claimed = AppSettings.instance.claimedAccount.trim();
      if (claimed.isNotEmpty) return claimed;
    }
    if (AppConfig.enableChangeAccount) {
      final String custom = AppSettings.instance.remoteAccount.trim();
      if (custom.isNotEmpty) return custom;
      final String fallback = AppConfig.toolsToken.trim();
      if (fallback.isNotEmpty) return fallback;
    }
    return derivedAccount();
  }

  /// 生效口令：claim 闸门开启且已保存 claim 口令时优先用它；其余情况沿用
  /// 原优先级（调试自定义 > `.env` > 默认 `123456`）。
  ///
  /// 自定义登录名是可猜的，服务端在 claim 时会换掉默认口令并一次性下发，
  /// 这里只是把新口令接到原有 MD5 校验链路上；闸门默认关闭，中控端 / TV 端
  /// 行为与改动前完全一致。
  static String password() {
    if (_claimEnabled) {
      final String claimed = AppSettings.instance.claimedPassword.trim();
      if (claimed.isNotEmpty) return claimed;
    }
    if (AppConfig.enableChangeAccount) {
      final String custom = AppSettings.instance.remotePassword.trim();
      if (custom.isNotEmpty) return custom;
    }
    final String fallback = AppConfig.toolsPassword.trim();
    if (fallback.isNotEmpty) return fallback;
    return defaultPassword;
  }

  /// 口令 MD5——HTTP 登录与 ws 握手提交的同一个值。
  static String passwordMd5() =>
      md5.convert(utf8.encode(password())).toString();

  /// 启动期校正账号：非调试包把已保存账号一律改写为派生值（不做旧号兼容）；
  /// 调试包保留手动值。
  ///
  /// claim 闸门开启且已有自定义登录名时，跳过派生值改写，保证重启后仍生效。
  /// 返回当前生效账号。
  static Future<String> enforceDerivedAccount() async {
    await AppSettings.instance.ensureLoaded();
    if (_claimEnabled) {
      final String claimed = AppSettings.instance.claimedAccount.trim();
      if (claimed.isNotEmpty) {
        // 同步调试字段，避免设置页仍显示旧的派生账号。
        if (AppSettings.instance.remoteAccount.trim() != claimed) {
          await AppSettings.instance.setRemoteAccount(claimed);
        }
        return claimed;
      }
    }
    if (AppConfig.enableChangeAccount) return account();
    final String derived = await derivedAccount();
    if (derived.isEmpty) return '';
    if (AppSettings.instance.remoteAccount.trim() != derived) {
      await AppSettings.instance.setRemoteAccount(derived);
    }
    return derived;
  }

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

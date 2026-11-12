import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_identity.dart';

/// 设备凭据：家长端把「设备身份」和「家长身份」拆成两套，互不替代。
///
/// 服务端以 `datas/register/users/<账号>`（内容为口令 MD5）为唯一校验源，
/// 两条链路各自提交自己那套凭据：
///
/// - **实时通道凭据**（[channelAccount] / [channelPassword]）：恒等于设备派生号
///   `<flavor>.<kind>.<设备号16hex>` + 默认口令 `123456`。这是设备身份证，
///   WebSocket 握手、心跳上报、设备表 commAccount 全用它，
///   **永不改名、永不禁用、不参与设置家长号**。
/// - **管理登录凭据**（[account] / [password]）：家长号优先，未设置时回落派生号。
///   用于 HTTP 登录（`/api/login`、`/api/admin/*`）与 `machine.parents`
///   可见性判定。家长号是「家长这个人」的身份，可跨设备、口令可自设/重置。
///
/// 账号作用域 `<flavor>.<kind>` 由宿主启动时通过 [configureAccountScope] 传入
/// （取自构建 flavor 与 `kindOfApp()` 的实际 kind，不在此处维护映射表）；
/// 设备号取 [DeviceIdentity] 解析结果的 16 位 hex（去掉连字符）。
///
/// [configureClaimEnabled] 只对 parent flavor 开启：它仅影响**管理登录**是否
/// 采用家长号；实时通道凭据永远走派生值分支，中控端 / TV 端行为完全不变。
class DeviceCredentials {
  const DeviceCredentials._();

  /// 默认口令（与服务端自动建档口令一致，见服务端 accounts.js）。
  static const String defaultPassword = '123456';

  /// 账号作用域 `<flavor>.<kind>`；由宿主启动时设置。
  static String _accountScope = '';

  /// 是否允许管理登录使用家长自定义登录名；默认关闭，由 parent flavor 显式开启。
  ///
  /// 只影响 [account] / [password]；[channelAccount] / [channelPassword]
  /// 恒为派生值，不受此闸门影响。
  static bool _claimEnabled = false;

  /// 宿主启动时设置账号作用域（如 `tv.tv`、`board.home`、`parent.parent`）。
  static void configureAccountScope(String scope) {
    _accountScope = scope.trim();
  }

  /// 是否允许 [account] / [password] 使用家长自定义登录名。
  ///
  /// 只有 parent flavor 传 true；其它宿主不调用（或传 false）时，
  /// 管理登录恒等于派生值，行为与历史版本完全一致。
  static void configureClaimEnabled(bool enabled) {
    _claimEnabled = enabled;
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

  /// **实时通道账号**：恒为设备派生号 `<flavor>.<kind>.<设备号16hex>`。
  ///
  /// 设备号不可用时返回空串，而不是仅返回作用域。与家长号彻底解耦，
  /// 永不因设置/更换家长号而改变。调试包沿用 `remoteAccount` / `.env` 覆盖。
  static Future<String> channelAccount() async {
    if (AppConfig.enableChangeAccount) {
      final String custom = AppSettings.instance.remoteAccount.trim();
      if (custom.isNotEmpty) return custom;
      final String fallback = AppConfig.toolsToken.trim();
      if (fallback.isNotEmpty) return fallback;
    }
    return derivedAccount();
  }

  /// **实时通道口令**：恒为默认口令 `123456`（调试包允许自定义）。
  ///
  /// 与家长号口令解耦：设置/重置家长号后实时通道仍用默认值连 ws，
  /// 派生号账号永不被禁用，故不存在「重置后实时通道登不上」的问题。
  static String channelPassword() {
    if (AppConfig.enableChangeAccount) {
      final String custom = AppSettings.instance.remotePassword.trim();
      if (custom.isNotEmpty) return custom;
    }
    final String fallback = AppConfig.toolsPassword.trim();
    if (fallback.isNotEmpty) return fallback;
    return defaultPassword;
  }

  /// 实时通道口令 MD5——ws 握手提交的值。
  static String channelPasswordMd5() =>
      md5.convert(utf8.encode(channelPassword())).toString();

  /// 派生账号；设备号不可用时返回空串，而不是仅返回作用域。
  static Future<String> derivedAccount() async {
    final String id = await deviceId();
    if (id.isEmpty || _accountScope.isEmpty) return '';
    return '$_accountScope.$id';
  }

  /// **管理登录账号**：家长号优先，未设置家长号时回落 [channelAccount]。
  ///
  /// 用于 `/api/login`、`/api/admin/*` 与 `machine.parents` 可见性判定。
  static Future<String> account() async {
    if (_claimEnabled) {
      await AppSettings.instance.ensureLoaded();
      final String claimed = AppSettings.instance.claimedAccount.trim();
      if (claimed.isNotEmpty) return claimed;
    }
    return channelAccount();
  }

  /// **管理登录口令**：家长号口令优先，未设置家长号时回落 [channelPassword]。
  ///
  /// 家长号口令可自设/重置（不再是一次性随机、只存本机），换设备凭
  /// 「家长号 + 口令」即可登录并看到同一批绑定关系。
  static String password() {
    if (_claimEnabled) {
      final String claimed = AppSettings.instance.claimedPassword.trim();
      if (claimed.isNotEmpty) return claimed;
    }
    return channelPassword();
  }

  /// 管理登录口令 MD5——HTTP `/api/login` / `/api/admin/login` 提交的值。
  static String passwordMd5() =>
      md5.convert(utf8.encode(password())).toString();

  /// 对任意明文取 MD5（与服务端口令摘要口径一致）。
  ///
  /// 供「跨设备登录 / 改口令」等需要提交用户新输入口令摘要的场景复用，
  /// 避免各页面直接依赖 crypto 包。
  static String md5Of(String text) =>
      md5.convert(utf8.encode(text)).toString();

  /// 启动期校正**实时通道账号**为派生值：非调试包把已保存账号抹回派生值。
  ///
  /// 只校正通道凭据；家长号（管理登录凭据）不受影响，即使已 claim，
  /// 通道账号也必须恒为派生值。返回当前生效的通道账号。
  static Future<String> enforceDerivedAccount() async {
    await AppSettings.instance.ensureLoaded();
    if (AppConfig.enableChangeAccount) return channelAccount();
    final String derived = await derivedAccount();
    if (derived.isEmpty) return '';
    if (AppSettings.instance.remoteAccount.trim() != derived) {
      await AppSettings.instance.setRemoteAccount(derived);
    }
    // 通道口令恒为默认，清掉调试期可能残留的自定义口令，确保派生号可登录。
    if (AppSettings.instance.remotePassword.isNotEmpty) {
      await AppSettings.instance.setRemotePassword('');
    }
    return derived;
  }
}

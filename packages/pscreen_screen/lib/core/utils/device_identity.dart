import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pscreen_screen/core/utils/platform_channel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备唯一编号：`xxxx-xxxx-xxxx-xxxx`（16 位十六进制，4 组）。
///
/// 取值优先级：
/// 1. **ANDROID_ID**（`Settings.Secure.ANDROID_ID`）——API 26+ 由「签名密钥 + 用户 +
///    设备」共同决定，卸载重装**不变**；API 26 以下为设备级值，同样跨卸载存活。
/// 2. **MediaDrm 设备唯一 ID**（Widevine）——个别盒子 ANDROID_ID 为空或全零时兜底。
///    注意：恢复出厂设置会变。
/// 3. **本地随机值**——两者都不可用时（桌面端调试、极个别机型）生成并持久化，
///    只在**当前安装**内稳定，卸载重装会变。
///
/// 原始值不足 16 位十六进制时统一用 MD5 取前 16 位收敛成固定长度，保证编号格式一致。
class DeviceIdentity {
  DeviceIdentity._();

  /// 全局单例。
  static final DeviceIdentity instance = DeviceIdentity._();

  /// 本地随机兜底值的持久化 key。
  static const String _keyFallback = 'app_device_id_fallback_v1';

  /// Android 2.2 时代所有设备共用的错误 ANDROID_ID，视为无效。
  static const String _knownBadAndroidId = '9774d56d682e549c';

  Future<String>? _pending;

  /// 解析设备唯一编号；并发调用共享同一次解析。
  Future<String> resolve() => _pending ??= _compute();

  Future<String> _compute() async {
    final ({String androidId, String mediaDrmId}) raw =
        await PlatformChannelService.instance.deviceIdentity();
    for (final String candidate in <String>[raw.androidId, raw.mediaDrmId]) {
      final String id = normalize(candidate);
      if (id.isNotEmpty) return id;
    }
    return normalize(await _localFallback());
  }

  /// 归一化原始设备标识为 `xxxx-xxxx-xxxx-xxxx`；无效值返回空串。
  ///
  /// - 16 位十六进制 → 直接分组（ANDROID_ID 的正常情况）
  /// - 其它非空且非无效值 → MD5 取前 16 位后分组
  /// - 空串 / 全零 / 已知错误值 → 空串（调用方继续尝试下一个来源）
  static String normalize(String raw) {
    final String value = raw.trim();
    if (value.isEmpty || _isInvalid(value)) return '';
    if (value.length == 16 && _isHex(value)) {
      return _group(value.toLowerCase());
    }
    final String digest = md5.convert(utf8.encode(value)).toString();
    return _group(digest.substring(0, 16));
  }

  /// 无可用设备标识时的本地兜底：随机生成并持久化（仅当前安装内稳定）。
  Future<String> _localFallback() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_keyFallback);
      if (saved != null && saved.length == 16 && _isHex(saved)) return saved;
      final String generated = _randomHex16();
      await prefs.setString(_keyFallback, generated);
      return generated;
    } catch (_) {
      // 持久化不可用（如测试环境）：退化为进程内随机值，不跨启动稳定。
      return _randomHex16();
    }
  }

  static String _randomHex16() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static String _group(String hex16) =>
      '${hex16.substring(0, 4)}-${hex16.substring(4, 8)}-'
      '${hex16.substring(8, 12)}-${hex16.substring(12, 16)}';

  static bool _isInvalid(String value) {
    final String lower = value.toLowerCase();
    if (lower == _knownBadAndroidId) return true;
    return !lower.contains(RegExp('[1-9a-f]'));
  }

  static bool _isHex(String value) =>
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
}

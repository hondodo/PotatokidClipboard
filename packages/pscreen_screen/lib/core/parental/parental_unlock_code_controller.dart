import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 解锁请求上行发送抽象（生产在 ParentalModule 里包 [RealtimeChannel.sendEvent]；
/// 测试用 Fake）。
typedef UnlockRequestSender = Future<bool> Function({
  required String event,
  required String to,
  required Map<String, dynamic> data,
});

/// 远程解锁短码状态（全局单例，[ChangeNotifier]）。
///
/// 锁屏出现时生成 6 位短码（60s 有效期、一次性）并**同码双发**两条
/// `parental_unlock_request`（方案 §4.2 定稿）：
/// ① `to` = `parental.ownerAccount`（owner 直投；阶段 3 已接通——服务端
///    config 到达时由 `applyServerConfig` 用 `machine.owner` 富化空值，
///    仍为空则回落 `1000001`）；
/// ② `to` = `'1000001'`（补会话线程可见性）。
/// 两条 `data` 完全相同（含同一短码），**手机端按短码去重**。
///
/// 访问方：锁屏 UI（展示 / 重新请求）与 `MessageCommandExecutor`
/// （`parental_unlock` 命令校验消费），经 DI（`ParentalModule`）注册。
class ParentalUnlockCodeController extends ChangeNotifier {
  ParentalUnlockCodeController._({
    DateTime Function()? now,
    Future<String> Function()? deviceIdProvider,
    String Function()? ownerAccountProvider,
  })  : _now = now ?? DateTime.now,
        _deviceIdProvider = deviceIdProvider ?? DeviceCredentials.deviceId,
        _ownerAccountProvider =
            ownerAccountProvider ?? _ownerFromConfig;

  /// 全局单例（可变：测试经 [debugCreateForTest] 替换，用后 [debugResetInstance] 还原）。
  static ParentalUnlockCodeController instance =
      ParentalUnlockCodeController._();

  /// 仅供测试：构造独立实例（不触碰全局单例、不挂计时器）。
  @visibleForTesting
  static ParentalUnlockCodeController debugCreateForTest({
    required DateTime Function() now,
    Future<String> Function()? deviceIdProvider,
    String Function()? ownerAccountProvider,
    UnlockRequestSender? sender,
  }) {
    final ParentalUnlockCodeController controller =
        ParentalUnlockCodeController._(
      now: now,
      deviceIdProvider: deviceIdProvider,
      ownerAccountProvider: ownerAccountProvider,
    );
    controller._sender = sender;
    return controller;
  }

  /// 仅供测试：还原全局单例。
  @visibleForTesting
  static void debugResetInstance() =>
      instance = ParentalUnlockCodeController._();

  /// 短码位数。
  static const int codeLength = 6;

  /// 短码有效期（方案 §4.2：60s 过期作废）。
  static const Duration codeTtl = Duration(seconds: 60);

  /// 解锁请求事件名（满足服务端 `EVENT_NAME_PATTERN`，服务端零改动）。
  static const String eventName = 'parental_unlock_request';

  /// 会话线程可见性补发目标（系统管理员账号）。
  static const String adminAccount = '1000001';

  final DateTime Function() _now;
  final Future<String> Function() _deviceIdProvider;
  final String Function() _ownerAccountProvider;

  UnlockRequestSender? _sender;
  KidWatchTimerController? _watched;
  bool _wasLocked = false;

  String? _code;
  int _expiresAtMs = 0;
  bool _consumed = false;
  String _reason = '';

  /// 有未送达的解锁请求（生成/补发时置位，任一目标受理后清除）。
  bool _pendingSend = false;
  Map<String, dynamic>? _pendingData;

  // ---- 只读 ----
  String? get code => _code;

  /// 最近一次签发原因（`quietHours` / `session:<id>` / `daily:<id>`）。
  String get reason => _reason;

  /// 短码已被 `parental_unlock` 命令消费（一次性）。
  bool get consumed => _consumed;

  /// 短码当前有效（存在、未消费、未过期）。
  bool get active =>
      _code != null &&
      !_consumed &&
      _now().millisecondsSinceEpoch < _expiresAtMs;

  /// 短码已过期（存在、未消费、超过 60s）。
  bool get expired =>
      _code != null &&
      !_consumed &&
      _now().millisecondsSinceEpoch >= _expiresAtMs;

  /// 剩余有效秒数（向上取整；无效时 0）。
  int get remainingSec {
    if (!active) return 0;
    final int remainMs = _expiresAtMs - _now().millisecondsSinceEpoch;
    return (remainMs + 999) ~/ 1000;
  }

  /// 绑定上行发送器（DI 注册时注入；测试注入 Fake）。
  void bindSender(UnlockRequestSender? sender) {
    _sender = sender;
  }

  /// 挂到计时器：锁屏出现（上升沿）自动生成并双发；解除（下降沿）作废旧码。
  /// 挂载时已处于锁屏（重启保持场景）立即补发。重复挂同一计时器幂等。
  void watch(KidWatchTimerController timer) {
    if (identical(_watched, timer)) return;
    unwatch();
    _watched = timer;
    _wasLocked = timer.locked;
    timer.addListener(_onTimerNotified);
    if (timer.locked) _issueIfIdle();
  }

  /// 解除挂载（DI unregister 时清理监听）。
  void unwatch() {
    final KidWatchTimerController? timer = _watched;
    if (timer == null) return;
    timer.removeListener(_onTimerNotified);
    _watched = null;
  }

  void _onTimerNotified() {
    final KidWatchTimerController? timer = _watched;
    if (timer == null) return;
    final bool locked = timer.locked;
    if (locked == _wasLocked) return;
    _wasLocked = locked;
    if (locked) {
      _issueIfIdle();
    } else {
      // 解锁（远程命令 / 本地验证 / 关模式）→ 旧码作废，防过期前被复用。
      invalidate();
    }
  }

  void _issueIfIdle() {
    if (active) return;
    final String reason = _watched?.lockReason ?? '';
    unawaited(issue(reason.isEmpty ? 'threshold' : reason));
  }

  /// 生成新短码（覆盖旧码）并同码双发解锁请求。
  ///
  /// 返回是否至少一条被服务端受理（离线返回 false，锁屏提示重新请求 /
  /// 登录成功后经 [flushPending] 按原码补发）。
  Future<bool> issue(String reason) async {
    final Random random = Random.secure();
    // 首位非 0：避免 `012345` 这类被当成数字解析的歧义。
    final StringBuffer buffer = StringBuffer(1 + random.nextInt(9));
    for (int i = 1; i < codeLength; i++) {
      buffer.write(random.nextInt(10));
    }
    _code = buffer.toString();
    _expiresAtMs = _now().millisecondsSinceEpoch + codeTtl.inMilliseconds;
    _consumed = false;
    _reason = reason;
    _pendingSend = true;
    notifyListeners();

    String deviceId = '';
    try {
      deviceId = await _deviceIdProvider();
    } catch (_) {
      // 设备号不可用时仍发送（置空），不阻断解锁请求。
    }
    final Map<String, dynamic> data = <String, dynamic>{
      'code': _code,
      'deviceId': deviceId,
      'reason': reason,
    };
    _pendingData = data;
    final bool ok = await _sendDouble(data);
    if (ok) _pendingSend = false;
    return ok;
  }

  /// 登录成功后补发未送达的解锁请求（重启时短码可能先于连接建立生成）。
  ///
  /// 按**原码**重发两条（手机端按 code 去重，重复无副作用）；
  /// 短码已过期/已消费/已送达时为空操作。
  Future<bool> flushPending() async {
    if (!_pendingSend || !active) return false;
    final Map<String, dynamic>? data = _pendingData;
    if (data == null) return false;
    final bool ok = await _sendDouble(data);
    if (ok) _pendingSend = false;
    return ok;
  }

  /// 校验并一次性消费短码：匹配 + 60s 未过期 + 未使用过。
  /// 全部满足才置为已消费（返回 true）；任一不满足返回 false（不抛异常）。
  bool consume(String raw) {
    final String? expected = _code;
    if (expected == null || _consumed) return false;
    if (_now().millisecondsSinceEpoch >= _expiresAtMs) return false;
    if (raw.trim() != expected) return false;
    _consumed = true;
    notifyListeners();
    return true;
  }

  /// 作废当前短码（解锁成功 / 关模式 / 换码前清理）。
  void invalidate() {
    if (_code == null && !_consumed && _reason.isEmpty) return;
    _code = null;
    _consumed = false;
    _expiresAtMs = 0;
    _reason = '';
    _pendingSend = false;
    _pendingData = null;
    notifyListeners();
  }

  /// 同码双发两条 `parental_unlock_request`（① owner 直投 + ② 1000001）。
  Future<bool> _sendDouble(Map<String, dynamic> data) async {
    final UnlockRequestSender? sender = _sender;
    if (sender == null) return false;
    final String owner = _ownerAccountProvider().trim();
    final String toOwner = owner.isEmpty ? adminAccount : owner;
    final List<bool> results = await Future.wait(<Future<bool>>[
      _safeSend(sender, toOwner, data),
      _safeSend(sender, adminAccount, data),
    ]);
    final bool ok = results.any((bool r) => r);
    Log.i(
      '[UnlockCode] 解锁请求双发 code=${data['code']} '
      'to=$toOwner/$adminAccount ok=$ok',
    );
    return ok;
  }

  Future<bool> _safeSend(
    UnlockRequestSender sender,
    String to,
    Map<String, dynamic> data,
  ) async {
    try {
      return await sender(event: eventName, to: to, data: data);
    } catch (e) {
      Log.error('[UnlockCode] 解锁请求发送失败(to=$to): $e');
      return false;
    }
  }

  /// owner 取当前生效 parental 配置的 `ownerAccount`（阶段 3 起服务端
  /// config 到达后即真实 `machine.owner`；空值由 [_sendDouble] 回落
  /// [adminAccount]）。
  static String _ownerFromConfig() =>
      ParentalStateController.instance.config.ownerAccount;
}

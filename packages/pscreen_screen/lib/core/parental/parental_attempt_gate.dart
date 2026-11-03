
import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 解锁防爆破闸门（全局单例）：连续错 5 次本地锁定 60s（方案 §4.2）。
///
/// 计数与锁定截止时间持久化在独立 key（[storageKey]，`parental_` 前缀——
/// 已被 `AppSettings.clearAllPersisted()` 的 `_isParentalStateKey` 豁免），
/// **重启不清**。锁定期间验证 UI 禁用输入，倒计时结束后自动放行。
///
/// 仅供 `ParentalVerificationSheet`（锁屏解锁 / 选人页 `locked` 闸门）调用。
class ParentalAttemptGate {
  ParentalAttemptGate._({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// 全局单例。
  static final ParentalAttemptGate instance = ParentalAttemptGate._();

  /// 仅供测试：用注入时钟构造独立实例（不触碰全局单例）。
  @visibleForTesting
  static ParentalAttemptGate debugCreateForTest(DateTime Function() now) =>
      ParentalAttemptGate._(now: now);

  /// 仅供测试：清空内存态（不改动持久化数据），避免跨用例串扰——
  /// 上一用例 FakeAsync 区间内创建的 Future 无法在下一用例刷新。
  @visibleForTesting
  void debugResetForTest() {
    _loading = null;
    _failCount = 0;
    _lockedUntilMs = 0;
  }

  /// 持久化 key（独立于 AppSettings 的全部键，重置不清理）。
  static const String storageKey = 'parental_attempt_gate_v1';

  /// 连续失败上限：达到即锁定。
  static const int maxFailures = 5;

  /// 锁定时长。
  static const Duration lockDuration = Duration(seconds: 60);

  final DateTime Function() _now;
  int _failCount = 0;
  int _lockedUntilMs = 0;
  Future<void>? _loading;

  /// 当前连续失败次数（0~[maxFailures]-1；触发锁定后归零）。
  int get failCount => _failCount;

  /// 是否处于锁定中。
  bool get locked => _now().millisecondsSinceEpoch < _lockedUntilMs;

  /// 锁定剩余秒数（向上取整；未锁定时 0）。
  int get remainingLockSec {
    if (!locked) return 0;
    final int remainMs = _lockedUntilMs - _now().millisecondsSinceEpoch;
    return (remainMs + 999) ~/ 1000;
  }

  /// 加载持久化状态（并发共享同一次；幂等）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _failCount = prefs.getInt('${storageKey}_fail') ?? 0;
      _lockedUntilMs = prefs.getInt('${storageKey}_until') ?? 0;
    } catch (e) {
      Log.error('[AttemptGate] 持久化读取失败: $e');
    }
  }

  /// 记一次失败：达 [maxFailures] 则锁定 [lockDuration] 并清零计数。
  ///
  /// 先 [ensureLoaded] 再落盘，避免加载前的写入覆盖持久化的锁定状态。
  Future<void> recordFailure() async {
    await ensureLoaded();
    _failCount += 1;
    if (_failCount >= maxFailures) {
      _failCount = 0;
      _lockedUntilMs =
          _now().millisecondsSinceEpoch + lockDuration.inMilliseconds;
      Log.i('[AttemptGate] 连续错 $maxFailures 次，锁定 ${lockDuration.inSeconds}s');
    }
    await _save();
  }

  /// 验证通过 / 新一轮开始：清零计数与锁定。
  Future<void> recordSuccess() async {
    await ensureLoaded();
    if (_failCount == 0 && _lockedUntilMs == 0) return;
    _failCount = 0;
    _lockedUntilMs = 0;
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${storageKey}_fail', _failCount);
      await prefs.setInt('${storageKey}_until', _lockedUntilMs);
    } catch (e) {
      Log.error('[AttemptGate] 持久化写入失败: $e');
    }
  }
}

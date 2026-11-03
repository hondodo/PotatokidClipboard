import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 儿童观看计时器（双计时熔断，全局单例，[ChangeNotifier]）。
///
/// 与 [SleepTimerController] **刻意分离**：后者是一次性会话定时器（重启不该
/// 继续倒数），本类是持久管控状态（重启必须继续）。混用会同时破坏两边。
///
/// **两个计时维度（按孩子分账）**：
/// - 单次连续观看 `sessionSecByChild`：进入锁屏 / 退后台超 5 分钟 / 换人时重置；
/// - 单日累计 `dailySecByChild`：日期翻转时清零。
///
/// **场景计入口径**：`live`/`clock`/`screensaver` 计入（屏保照常累计），
/// `settings`/锁屏不计入；退后台超过 5 分钟重置 session（daily 不动）。
///
/// **锁屏判定（逐人比较）**：任一选中孩子 `sessionSec >= 自己档案的
/// sessionLimitMin`（daily 同理）即到阈值——与「组合取最小」等价，但
/// 每个孩子与**自己的**限额比。任一限额为 0/缺失 = 该维度不启用。
///
/// 持久化用独立 key（[storageKey]），**不放进 [AppSettings]**——因为
/// `AppSettings.clearAllPersisted()` 会清空全部键；本类的键在
/// `clearAllPersisted` 中被显式豁免（见该方法），家长解除时走显式清除入口。
class KidWatchTimerController extends ChangeNotifier {
  KidWatchTimerController._({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// 全局单例（生产用真实时钟；测试经 [debugCreateForTest] 注入可控时钟）。
  static final KidWatchTimerController instance =
      KidWatchTimerController._();

  /// 仅供测试：用注入时钟构造独立实例（不触碰全局单例）。
  @visibleForTesting
  static KidWatchTimerController debugCreateForTest(
          DateTime Function() now) =>
      KidWatchTimerController._(now: now);

  /// 时钟（测试注入；默认真实时间）。
  final DateTime Function() _now;

  /// 持久化 key（独立于 AppSettings 的全部键）。
  static const String storageKey = 'kid_watch_timer_v1';

  /// 计时粒度（每秒累加一次）。
  static const Duration tickInterval = Duration(seconds: 1);

  /// 退后台超过该时长 → 重置 session（daily 不动）。
  static const Duration backgroundResetThreshold = Duration(minutes: 5);

  /// daily 锁解锁后的放行窗口（方案 B：窗口内跳过 daily 判锁）。
  static const Duration dailyUnlockGrace = Duration(minutes: 10);

  // ---- 持久化状态 ----
  String _dateKey = '';
  final Map<String, int> _sessionSecByChild = <String, int>{};
  final Map<String, int> _dailySecByChild = <String, int>{};
  final Map<String, int> _unlockGraceUntilMs = <String, int>{};
  List<String> _activeChildIds = <String>[];

  // ---- 运行时状态（不持久化） ----
  bool _enabled = false;
  bool _viewingScene = false;
  bool _appForeground = true;
  int? _pausedAtMs;
  Timer? _ticker;
  int _lastSaveMs = 0;

  /// 各档案限额（由 ParentalStateController 注入：id → profile）。
  Map<String, ChildProfile> _profiles = <String, ChildProfile>{};

  /// quietHours 并集（由 ParentalStateController 注入）。
  List<QuietHour> _quietHours = const <QuietHour>[];

  /// 到阈值（进锁屏）回调；宿主注入（阶段 1 先接占位锁屏）。
  VoidCallback? onThresholdReached;

  /// 解锁成功回调（宿主/命令执行器调用 [unlock] 后触发）。
  VoidCallback? onUnlocked;

  // ---- 对外只读 ----
  bool get enabled => _enabled;
  List<String> get activeChildIds => List<String>.unmodifiable(_activeChildIds);
  bool get locked => _locked;
  bool _locked = false;

  /// 最近一次到阈值的原因（`quietHours` / `session:<id>` / `daily:<id>`）；
  /// 解除后保留至下次到阈值，解锁请求的 `reason` 字段取此值。
  String _lockReason = '';
  String get lockReason => _lockReason;

  /// 当前是否在「计入」的观看场景。
  bool get counting => _enabled && _viewingScene && _appForeground && !_locked;

  String get dateKey => _dateKey;

  /// 某孩子已看的单次连续时长（秒）。
  int sessionSecOf(String childId) => _sessionSecByChild[childId] ?? 0;

  /// 某孩子已看的单日累计时长（秒）。
  int dailySecOf(String childId) => _dailySecByChild[childId] ?? 0;

  /// 全部分账时长快照（上报用）。
  Map<String, int> get sessionSecByChild => Map<String, int>.unmodifiable(_sessionSecByChild);
  Map<String, int> get dailySecByChild => Map<String, int>.unmodifiable(_dailySecByChild);

  /// 单次连续剩余（秒）：取当前组合中**最先到阈值**的孩子的剩余时间
  ///（锁屏展示「剩余」用；无启用限额时返回 null）。
  int? get remainingSessionSec {
    int? min;
    for (final String id in _activeChildIds) {
      final int limit = _profiles[id]?.sessionLimitMin ?? 0;
      if (limit <= 0) continue;
      final int remain = limit * 60 - sessionSecOf(id);
      if (min == null || remain < min) min = remain;
    }
    return min;
  }

  /// 单日累计剩余（秒）：同上，取最先到阈值者。
  int? get remainingDailySec {
    int? min;
    for (final String id in _activeChildIds) {
      final int limit = _profiles[id]?.dailyLimitMin ?? 0;
      if (limit <= 0) continue;
      final int remain = limit * 60 - dailySecOf(id);
      if (min == null || remain < min) min = remain;
    }
    return min;
  }

  /// 配置/选人变化时由 ParentalStateController 注入。
  ///
  /// [enabled]：生效判定式结果；[profiles]：各档案限额；[quietHours]：并集；
  /// [activeChildIds]：当前选中孩子。
  void configure({
    required bool enabled,
    required Map<String, ChildProfile> profiles,
    required List<QuietHour> quietHours,
    required List<String> activeChildIds,
  }) {
    final bool wasEnabled = _enabled;
    _enabled = enabled;
    _profiles = profiles;
    _quietHours = quietHours;
    _applyActiveChildren(activeChildIds);
    if (!enabled) {
      _locked = false;
      _stopTicker();
    } else {
      _ensureTicker();
      _checkThreshold();
    }
    if (wasEnabled != enabled) {
      _save();
    }
    notifyListeners();
  }

  /// 场景切换（宿主注入：live/clock/screensaver 计入，settings/锁屏不计入）。
  void setViewingScene(bool viewing) {
    if (_viewingScene == viewing) return;
    _viewingScene = viewing;
    if (viewing) _checkThreshold();
    notifyListeners();
  }

  /// App 前后台切换（宿主经生命周期注入）。退后台超 [backgroundResetThreshold]
  /// → 结算并重置 session（daily 不动）。
  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (!foreground) {
      _pausedAtMs = _now().millisecondsSinceEpoch;
    } else {
      final int? pausedAt = _pausedAtMs;
      _pausedAtMs = null;
      if (pausedAt != null &&
          _now().millisecondsSinceEpoch - pausedAt >=
              backgroundResetThreshold.inMilliseconds) {
        _resetSessions('退后台超5分钟');
      }
      if (_viewingScene) _checkThreshold();
    }
    notifyListeners();
  }

  /// 换人（选人页确认 / 家长改档案）：
  /// **仅新加入孩子从 0 起算**，仍在组合中的孩子 session 不清零（堵「加人续命」）；
  /// 离开的孩子移除其 session。daily 不受换人影响。
  void _applyActiveChildren(List<String> ids) {
    final List<String> next = ids.toSet().toList(growable: false);
    final List<String> prev = _activeChildIds;
    for (final String id in next) {
      if (!prev.contains(id)) {
        _sessionSecByChild[id] = 0; // 新加入 → 从 0 起算
      }
    }
    for (final String id in prev) {
      if (!next.contains(id)) {
        _sessionSecByChild.remove(id); // 离开 → 移除其 session
      }
    }
    _activeChildIds = next;
    _save();
  }

  /// 到阈值判定（逐人比较各自档案限额 + quietHours）。
  void _checkThreshold() {
    if (!_enabled || _locked) return;
    final DateTime now = _now();
    final int nowMs = now.millisecondsSinceEpoch;

    // 1) quietHours（并集）：命中即到阈值。
    if (_inQuietHours(now)) {
      _fireThreshold('quietHours');
      return;
    }

    // 2) 逐人比较 session / daily 限额。
    for (final String id in _activeChildIds) {
      final ChildProfile? profile = _profiles[id];
      if (profile == null) continue;
      final int sessionLimit = profile.sessionLimitMin;
      if (sessionLimit > 0 && sessionSecOf(id) >= sessionLimit * 60) {
        _fireThreshold('session:$id');
        return;
      }
      final int dailyLimit = profile.dailyLimitMin;
      if (dailyLimit > 0 &&
          dailySecOf(id) >= dailyLimit * 60 &&
          nowMs >= (_unlockGraceUntilMs[id] ?? 0)) {
        _fireThreshold('daily:$id');
        return;
      }
    }
  }

  bool _inQuietHours(DateTime now) {
    if (_quietHours.isEmpty) return false;
    final int minuteOfDay = now.hour * 60 + now.minute;
    for (final QuietHour q in _quietHours) {
      if (q.contains(minuteOfDay)) return true;
    }
    return false;
  }

  void _fireThreshold(String reason) {
    _locked = true;
    _lockReason = reason;
    _stopTicker();
    Log.i('[KidWatchTimer] 到阈值进锁屏: $reason');
    _save();
    notifyListeners();
    onThresholdReached?.call();
  }

  /// 解锁（远程命令 / PIN / 算术）。为 daily 锁的孩子写入放行窗口
  /// [dailyUnlockGrace]（窗口内跳过 daily 判锁，防解锁即再锁的死循环）。
  void unlock({String? childId}) {
    if (!_locked) return;
    _locked = false;
    final int until = _now().millisecondsSinceEpoch +
        dailyUnlockGrace.inMilliseconds;
    final List<String> targets =
        childId != null && _activeChildIds.contains(childId)
            ? <String>[childId]
            : _activeChildIds;
    for (final String id in targets) {
      _unlockGraceUntilMs[id] = until;
      // 单次 session 一并清零：session 维度没有放行窗口，不清零则
      // _checkThreshold 立即回锁、解锁形同虚设（方案 §3.2 解锁后开启
      // 新一轮单次观看；daily 靠放行窗口保持不动）。
      _sessionSecByChild[id] = 0;
    }
    Log.i('[KidWatchTimer] 解锁，daily 放行窗口至 +${dailyUnlockGrace.inMinutes}min');
    _save();
    _ensureTicker();
    _checkThreshold();
    notifyListeners();
    onUnlocked?.call();
  }

  /// 家长取消儿童模式 / 显式清除：清零全部计时与放行窗口。
  void clearAll() {
    _sessionSecByChild.clear();
    _dailySecByChild.clear();
    _unlockGraceUntilMs.clear();
    _activeChildIds = <String>[];
    _locked = false;
    _dateKey = _dateKeyOf(_now());
    _stopTicker();
    _save();
    notifyListeners();
  }

  void _resetSessions(String reason) {
    if (_sessionSecByChild.isEmpty) return;
    Log.i('[KidWatchTimer] 重置单次连续观看: $reason');
    for (final String id in _sessionSecByChild.keys) {
      _sessionSecByChild[id] = 0;
    }
    _save();
    notifyListeners();
  }

  // ---- 计时驱动 ----

  void _ensureTicker() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final DateTime now = _now();
    // 日期翻转：清零 daily（每次 tick 校验）。
    final String key = _dateKeyOf(now);
    if (key != _dateKey) {
      _dateKey = key;
      _dailySecByChild.clear();
      _unlockGraceUntilMs.clear();
      _save();
      notifyListeners();
    }
    if (!counting) return; // settings/锁屏/后台/未启用 → 不计入
    for (final String id in _activeChildIds) {
      _sessionSecByChild[id] = (_sessionSecByChild[id] ?? 0) + 1;
      _dailySecByChild[id] = (_dailySecByChild[id] ?? 0) + 1;
    }
    // 每秒写盘成本高：每 5 秒落盘一次即可（重启最多丢 4 秒，验收可接受）。
    final int nowMs = now.millisecondsSinceEpoch;
    if (nowMs - _lastSaveMs >= 5000) _save();
    _checkThreshold();
    notifyListeners();
  }

  // ---- 持久化 ----

  Future<void> ensureLoaded() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _dateKey = _dateKeyOf(_now());
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(decoded);
      _dateKey = (data['dateKey'] as String?) ?? _dateKeyOf(_now());
      _sessionSecByChild._addAllInt(data['sessionSecByChild']);
      _dailySecByChild._addAllInt(data['dailySecByChild']);
      _unlockGraceUntilMs._addAllInt(data['unlockGraceUntilMs']);
      _activeChildIds = ((data['activeChildIds'] as List?) ?? const <String>[])
          .whereType<String>()
          .toList(growable: false);
      // 跨日遗留：若 dateKey 不是今天，daily 视为已翻转清零。
      final String today = _dateKeyOf(_now());
      if (_dateKey != today) {
        _dateKey = today;
        _dailySecByChild.clear();
        _unlockGraceUntilMs.clear();
      }
      if (_enabled) _ensureTicker();
    } catch (e) {
      Log.error('[KidWatchTimer] 持久化读取失败: $e');
    }
  }

  Future<void> _save() async {
    _lastSaveMs = _now().millisecondsSinceEpoch;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<String, dynamic>{
          'dateKey': _dateKey,
          'sessionSecByChild': _sessionSecByChild,
          'dailySecByChild': _dailySecByChild,
          'unlockGraceUntilMs': _unlockGraceUntilMs,
          'activeChildIds': _activeChildIds,
        }),
      );
    } catch (e) {
      Log.error('[KidWatchTimer] 持久化写入失败: $e');
    }
  }

  static String _dateKeyOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}

/// 扩展：把 `Map<String, dynamic>` 里的整数字段并入目标 map（坏值跳过）。
extension _IntMapX on Map<String, int> {
  void _addAllInt(Object? raw) {
    if (raw is! Map) return;
    raw.forEach((dynamic k, dynamic v) {
      if (k is String && v is int && v >= 0) this[k] = v;
    });
  }
}

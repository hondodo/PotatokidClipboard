import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 儿童模式状态唯一持有者（全局单例，[ChangeNotifier]）。
///
/// 持有 parental 配置、`activeChildIds` 与 [KidWatchTimerController]。
/// 订阅者：开机选人页、`IptvBloc`、锁屏页、`ReportingService`。
///
/// **配置来源分阶段**：
/// - 阶段 1/2：读**本地临时配置**（SharedPreferences 手写 key，[storageKey]），
///   后台尚无 parental 表单，用于独立验收（不声称端到端）；
/// - 阶段 3：切换为读服务端 config（`parental` 字段），本地配置降级为调试入口。
/// 两版**接口一致**，调用方无感。
class ParentalStateController extends ChangeNotifier {
  ParentalStateController._();

  /// 全局单例。
  static final ParentalStateController instance = ParentalStateController._();

  /// 本地临时配置 key（阶段 1/2 过渡；阶段 3 后为调试入口）。
  static const String storageKey = 'parental_local_config_v1';

  ParentalConfig _config = const ParentalConfig();
  List<String> _activeChildIds = const <String>[];
  bool _loaded = false;
  Future<void>? _loading;

  /// 选人确认 / 换人时的回调（宿主注入：发 `parental_child_active` 上报）。
  void Function(List<String> childIds)? onActiveChildrenChanged;

  /// config 更新广播前的回调（阶段 3 服务端 config 到达时注入）。
  void Function(ParentalConfig config)? onConfigApplied;

  // ---- 只读 ----
  ParentalConfig get config => _config;

  /// 生效判定式（全文统一）：`mode === 'on' && children` 非空。
  bool get enabled => _config.enabled;

  /// 当前选中的孩子（已过滤悬空 id）。
  List<String> get activeChildIds =>
      _config.resolveActiveChildIds(_activeChildIds);

  /// 选中档案列表。
  List<ChildProfile> get activeProfiles => _config.profilesOf(activeChildIds);

  bool get loaded => _loaded;

  KidWatchTimerController get timer => KidWatchTimerController.instance;

  /// 加载本地临时配置（首次调用真正读取；并发共享同一次）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          _config = ParentalConfig.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
      _activeChildIds = _config.resolveActiveChildIds(
        _activeChildIds.isEmpty ? _config.activeChildIds : _activeChildIds,
      );
      _loaded = true;
      _syncTimer();
    } catch (e) {
      Log.error('[ParentalState] 本地配置读取失败: $e');
      _loaded = true;
    }
    notifyListeners();
  }

  /// 应用一份 parental 配置（阶段 1 为本地临时配置；阶段 3 为服务端 config）。
  ///
  /// 生效判定式不再成立时（`mode !== 'on'` 或 children 被清空）：
  /// 停计时、复原白名单/黑名单、清空 activeChildIds、作废短码、解除锁屏。
  Future<void> applyConfig(ParentalConfig config, {bool persist = false}) async {
    _config = config;
    // 无效档案 id：部分悬空 → 过滤后继续用剩余；全部悬空 → 视为未选。
    _activeChildIds = config.resolveActiveChildIds(_activeChildIds);
    if (!config.enabled) {
      _activeChildIds = const <String>[];
      timer.clearAll();
    }
    if (persist) await _save();
    _syncTimer();
    onConfigApplied?.call(config);
    notifyListeners();
  }

  /// 写入本地临时配置（阶段 1 调试入口 / 阶段 3 缓存兜底）。
  Future<void> saveLocalConfig(ParentalConfig config) async {
    _config = config;
    _activeChildIds = config.resolveActiveChildIds(_activeChildIds);
    await _save();
    _syncTimer();
    notifyListeners();
  }

  /// 选人页确认 / 换人：
  /// 驱动 ① IptvBloc 重放 ② KidWatchTimer 按分账换人 ③ 上报 `parental_child_active`。
  Future<void> setActiveChildren(List<String> ids) async {
    final List<String> next = _config.resolveActiveChildIds(ids);
    if (next.length == activeChildIds.length &&
        next.every(activeChildIds.contains)) {
      return; // 无变化
    }
    _activeChildIds = next;
    await _save();
    _syncTimer();
    onActiveChildrenChanged?.call(next);
    notifyListeners();
  }

  /// 把配置/选人状态同步进 [KidWatchTimerController]（限额、quietHours 并集、选中孩子）。
  void _syncTimer() {
    final Map<String, ChildProfile> profiles = <String, ChildProfile>{
      for (final ChildProfile c in _config.children) c.id: c,
    };
    timer.configure(
      enabled: enabled,
      profiles: profiles,
      quietHours: _config.quietHoursUnion(activeChildIds),
      activeChildIds: activeChildIds,
    );
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_config.toJson()));
    } catch (e) {
      Log.error('[ParentalState] 本地配置写入失败: $e');
    }
  }
}

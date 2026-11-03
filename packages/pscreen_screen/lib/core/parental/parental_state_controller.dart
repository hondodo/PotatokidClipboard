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
/// **配置来源与双源优先级（阶段 3 定稿）**：
/// - 服务端 config 的 `parental` 为**对象**（管理端已配置）→ 以服务端为准：
///   覆盖内存配置并写入 [serverStorageKey] 缓存，启动先读缓存立即生效；
/// - 服务端 `parental` 为 null/缺失（管理端未配置）→ 本地调试配置
///   （[storageKey]，阶段 1/2 临时配置降级而来）完全生效；
/// - [saveLocalConfig] 仍即时生效，但服务端已配置时仅维持到下一次 config
///   推送 / 重启——本地入口降级为调试用途，避免双源长期打架。
///
/// 选中状态与配置来源**解耦**，独立持久化在 [activeIdsStorageKey]：服务端每次
/// 推送都带着管理端的默认预选，若不分离，推送会把电视端的选人结果冲回去。
class ParentalStateController extends ChangeNotifier {
  ParentalStateController._();

  /// 全局单例。
  static final ParentalStateController instance = ParentalStateController._();

  /// 本地调试配置 key（阶段 1/2 临时配置；阶段 3 起为调试入口，仅
  /// [saveLocalConfig] 写入，服务端已配置时其内容不参与生效）。
  static const String storageKey = 'parental_local_config_v1';

  /// 服务端 parental 缓存 key（仅 [applyServerConfig] 在服务端配置存在时写入，
  /// 管理端清除配置时移除）。
  static const String serverStorageKey = 'parental_server_config_v1';

  /// 选中档案 id 列表 key（电视端自己的选择，与配置来源解耦）。
  static const String activeIdsStorageKey = 'parental_active_ids_v1';

  ParentalConfig _config = const ParentalConfig();
  List<String> _activeChildIds = const <String>[];
  bool _loaded = false;
  Future<void>? _loading;

  /// 当前生效配置是否来自服务端（管理端已配置 parental）。
  bool _serverConfigured = false;

  /// 选人确认 / 换人时的回调（宿主注入：发 `parental_child_active` 上报）。
  void Function(List<String> childIds)? onActiveChildrenChanged;

  /// config 更新广播前的回调（服务端 config 到达时注入）。
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

  /// 管理端已配置 parental（本地调试配置此时不参与生效，仅即时覆盖）。
  bool get serverConfigured => _serverConfigured;

  bool get loaded => _loaded;

  KidWatchTimerController get timer => KidWatchTimerController.instance;

  /// 加载缓存配置（首次调用真正读取；并发共享同一次）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // 1) 配置：服务端缓存优先，其次本地调试配置（启动即生效，不等网络）。
      final Object? serverRaw = _tryDecode(prefs.getString(serverStorageKey));
      if (serverRaw is Map) {
        _config = ParentalConfig.fromJson(Map<String, dynamic>.from(serverRaw));
        _serverConfigured = true;
      } else {
        _serverConfigured = false;
        final Object? localRaw = _tryDecode(prefs.getString(storageKey));
        if (localRaw is Map) {
          _config =
              ParentalConfig.fromJson(Map<String, dynamic>.from(localRaw));
        }
      }
      // 2) 选中状态独立读取；缺省回退配置里的默认预选，再过滤悬空 id
      //    （部分悬空 → 保留剩余；全部悬空 → 视为未选，回退选人页）。
      final Object? activeRaw =
          _tryDecode(prefs.getString(activeIdsStorageKey));
      if (activeRaw is List) {
        _activeChildIds = activeRaw.whereType<String>().toList(growable: false);
      }
      _activeChildIds = _config.resolveActiveChildIds(
        _activeChildIds.isEmpty ? _config.activeChildIds : _activeChildIds,
      );
      _loaded = true;
      _syncTimer();
    } catch (e) {
      Log.error('[ParentalState] 配置读取失败: $e');
      _loaded = true;
    }
    notifyListeners();
  }

  /// 应用服务端 config 帧 / `sendReport` 回包中的 `parental`（权威信号）。
  ///
  /// - `parental` 是 Map → 管理端已配置：以服务端为准（覆盖本地调试配置），
  ///   `ownerAccount` 为空时用同帧 `owner`（`machine.owner`）富化，写
  ///   [serverStorageKey] 缓存后走 [applyConfig] 广播；
  /// - `parental` 为 null/缺失且此前有服务端缓存 → 管理端已清除：清缓存、
  ///   回退本地调试配置；本就无缓存（本地调试生效中）→ 不动作。
  Future<void> applyServerConfig(Map<String, dynamic> config) async {
    try {
      final Object? parental = config['parental'];
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (parental is Map) {
        final Map<String, dynamic> json = Map<String, dynamic>.from(parental);
        // ownerAccount 接通（方案 §2.2）：空值回落同帧 owner（machine.owner），
        // 仍空则由解锁双发回退 1000001。
        final String ownerAccount =
            (json['ownerAccount'] as String?)?.trim() ?? '';
        if (ownerAccount.isEmpty) {
          final Object? owner = config['owner'];
          if (owner is String && owner.trim().isNotEmpty) {
            json['ownerAccount'] = owner.trim();
          }
        }
        final ParentalConfig next = ParentalConfig.fromJson(json);
        // 首次拿到服务端配置且电视端尚无选择 → 以服务端默认预选起步。
        if (_activeChildIds.isEmpty) {
          _activeChildIds = next.activeChildIds;
        }
        _serverConfigured = true;
        await prefs.setString(serverStorageKey, jsonEncode(json));
        await applyConfig(next);
      } else if (_serverConfigured || prefs.containsKey(serverStorageKey)) {
        // 管理端清除了 parental → 回退本地调试配置（服务端不再说了算）。
        _serverConfigured = false;
        await prefs.remove(serverStorageKey);
        ParentalConfig local = const ParentalConfig();
        final Object? localRaw = _tryDecode(prefs.getString(storageKey));
        if (localRaw is Map) {
          local =
              ParentalConfig.fromJson(Map<String, dynamic>.from(localRaw));
        }
        await applyConfig(local);
      }
    } catch (e) {
      Log.error('[ParentalState] 服务端配置应用失败: $e');
    }
  }

  /// 应用一份 parental 配置并广播（[applyServerConfig] 等共用的预留口）。
  ///
  /// 生效判定式不再成立时（`mode !== 'on'` 或 children 被清空）：
  /// 停计时、复原白名单/黑名单、清空 activeChildIds、作废短码、解除锁屏。
  Future<void> applyConfig(ParentalConfig config, {bool persist = false}) async {
    _config = config;
    // 无效档案 id：部分悬空 → 过滤后继续用剩余；全部悬空 → 视为未选。
    _activeChildIds = config.resolveActiveChildIds(_activeChildIds);
    if (!config.enabled) {
      _activeChildIds = const <String>[];
      await _saveActiveIds(const <String>[]);
      timer.clearAll();
    }
    if (persist) await _save();
    _syncTimer();
    onConfigApplied?.call(config);
    notifyListeners();
  }

  /// 写入本地调试配置（阶段 3：调试入口；服务端已配置时仅即时生效，
  /// 下一次 config 推送 / 重启后仍以服务端为准）。
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
      // 无变化：仍落盘一次，确保「已确认过的选择」不依赖配置默认值兜底；
      // 回调照发——选人页「确认」即上报（家长端事件流以确认动作而非
      // 是否变化为准，重复确认幂等）。
      await _saveActiveIds(next);
      onActiveChildrenChanged?.call(next);
      return;
    }
    _activeChildIds = next;
    await _saveActiveIds(next);
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

  /// 写本地调试配置（[storageKey]）。
  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_config.toJson()));
    } catch (e) {
      Log.error('[ParentalState] 本地配置写入失败: $e');
    }
  }

  /// 写选中状态（[activeIdsStorageKey]，与配置来源解耦）。
  Future<void> _saveActiveIds(List<String> ids) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeIdsStorageKey, jsonEncode(ids));
    } catch (e) {
      Log.error('[ParentalState] 选中状态写入失败: $e');
    }
  }

  /// 容错解析缓存 JSON（坏数据返回 null，不让单条脏数据打断启动）。
  static Object? _tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

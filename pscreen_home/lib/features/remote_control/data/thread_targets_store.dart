import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// 遥控会话的目标设备（本机维护）。
///
/// 不再使用 tvs.json 预设：会话列表只显示这里添加过的账号，
/// 通过会话页右上角「+」手动输入或扫码添加。
class ThreadTargetsStore {
  ThreadTargetsStore._();

  static final ThreadTargetsStore instance = ThreadTargetsStore._();

  static const String _key = 'remote_thread_targets';

  final StreamController<void> _changes = StreamController<void>.broadcast();

  late SharedPreferences _prefs;
  bool _loaded = false;
  List<String> _targets = <String>[];

  /// 列表变化通知（新增目标后刷新会话列表）。
  Stream<void> get changes => _changes.stream;

  /// 已添加的目标账号（添加顺序）。
  List<String> get targets => List<String>.unmodifiable(_targets);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _targets = _prefs.getStringList(_key) ?? <String>[];
    _loaded = true;
  }

  /// 添加目标；已存在则返回 false（不重复、不通知）。
  Future<bool> add(String account) async {
    final String target = account.trim();
    if (!_loaded || target.isEmpty || _targets.contains(target)) return false;
    _targets = <String>[..._targets, target];
    await _prefs.setStringList(_key, _targets);
    _changes.add(null);
    return true;
  }

  /// 移除目标（列表长按删除）。
  Future<void> remove(String account) async {
    if (!_loaded || !_targets.contains(account)) return;
    _targets = <String>[..._targets]..remove(account);
    await _prefs.setStringList(_key, _targets);
    _changes.add(null);
  }
}

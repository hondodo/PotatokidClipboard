import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 记录每个频道最近一次**可用**的播放源 URL（全局单例）。
///
/// 存的是 URL 而非序号：频道源列表变化（增删/顺序调整）时，
/// 只要该 URL 仍存在于该频道 sources 中就能优先从它起播；若已被移除则回落从首源起播。
///
/// 数据以 JSON 字符串存入 SharedPreferences，键为 `iptv_channel_source_v1`。
class ChannelSourceCache {
  ChannelSourceCache._();

  /// 全局单例。
  static final ChannelSourceCache instance = ChannelSourceCache._();

  static const String _key = 'iptv_channel_source_v1';
  static const String _channelKey = 'iptv_last_channel_v1';

  final Map<String, String> _map = <String, String>{};
  bool _loaded = false;
  String? _lastChannel;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null) return;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _map.addAll(decoded.cast<String, String>());
      }
    } catch (_) {
      // 解析失败则忽略，视为无历史记录。
    }
  }

  /// 该频道上次记住的可用源 URL；无记录返回 null。
  Future<String?> preferredSourceOf(String channelName) async {
    await _ensureLoaded();
    return _map[channelName];
  }

  /// 记录某频道的可用源 URL。
  Future<void> rememberSource(String channelName, String url) async {
    await _ensureLoaded();
    _map[channelName] = url;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_map));
    } catch (_) {
      // 写入失败不阻断播放。
    }
  }

  /// 上次播放的频道名；无记录返回 null。
  Future<String?> lastChannelName() async {
    await _ensureLoaded();
    if (_lastChannel == null) {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        _lastChannel = prefs.getString(_channelKey);
      } catch (_) {
        // 读取失败视为无记录。
      }
    }
    return _lastChannel;
  }

  /// 记录上次播放的频道名。
  Future<void> rememberChannel(String channelName) async {
    await _ensureLoaded();
    _lastChannel = channelName;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_channelKey, channelName);
    } catch (_) {
      // 写入失败不阻断播放。
    }
  }
}
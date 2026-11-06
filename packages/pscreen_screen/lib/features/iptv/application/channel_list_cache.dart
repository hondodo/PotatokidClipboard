import 'dart:convert';

import 'package:pscreen_screen/features/iptv/domain/models/final_channels.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 最终频道列表的持久化缓存（全局单例）。
///
/// 保存服务端返回的整份 payload（含 `version`），下次启动直接用缓存起播，
/// 再拿缓存版本向服务端做 ETag 比对；版本一致时不需要重新下载列表。
/// 不做过期淘汰：拉取失败时继续使用旧列表，由页面做轻提示。
class ChannelListCache {
  ChannelListCache._();

  /// 全局单例。
  static final ChannelListCache instance = ChannelListCache._();

  static const String _key = 'iptv_final_channels_v1';

  /// 读取缓存；无缓存或解析失败返回 null。
  Future<FinalChannelsPayload?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final FinalChannelsPayload payload =
          FinalChannelsPayload.fromJson(decoded.cast<String, dynamic>());
      return payload.channels.isEmpty ? null : payload;
    } catch (_) {
      // 缓存损坏视为无缓存。
      return null;
    }
  }

  /// 写入最新 payload；空列表不写入，避免清掉旧缓存。
  Future<void> save(FinalChannelsPayload payload) async {
    if (payload.channels.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(payload.toJson()));
    } catch (_) {
      // 写入失败不阻断加载。
    }
  }
}

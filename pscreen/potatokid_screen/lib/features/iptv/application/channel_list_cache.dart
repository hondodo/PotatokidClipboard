import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 直播频道列表的持久化缓存（全局单例）。
///
/// 负责把「线上频道列表」序列化写入 SharedPreferences，供下次启动时**先用缓存**、
/// 等线上加载完成后再替换；即使用户离线/加载失败也能继续用上一次成功的列表播放。
///
/// 数据为 JSON 字符串，键 `iptv_channels_v1`；读取/写入失败都不阻断主流程。
class ChannelListCache {
  ChannelListCache._();

  /// 全局单例。
  static final ChannelListCache instance = ChannelListCache._();

  static const String _key = 'iptv_channels_v1';

  /// 读取缓存的频道列表；无缓存或解析失败返回 null。
  Future<List<IptvChannel>?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final List<IptvChannel> channels = <IptvChannel>[];
      for (final dynamic item in decoded) {
        if (item is! Map) continue;
        final IptvChannel channel = _fromMap(item.cast<String, dynamic>());
        if (channel.name.isNotEmpty && channel.sources.isNotEmpty) {
          channels.add(channel);
        }
      }
      return channels.isEmpty ? null : channels;
    } catch (_) {
      // 缓存损坏视为无缓存。
      return null;
    }
  }

  /// 写入频道列表（空列表不写入，避免清掉旧缓存）。
  Future<void> save(List<IptvChannel> channels) async {
    if (channels.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(<dynamic>[
          for (final IptvChannel c in channels)
            <String, dynamic>{
              'name': c.name,
              'sources': c.sources,
              if (c.logo != null) 'logo': c.logo,
              if (c.group != null) 'group': c.group,
            },
        ]),
      );
    } catch (_) {
      // 写入失败不阻断加载。
    }
  }

  static IptvChannel _fromMap(Map<String, dynamic> map) => IptvChannel(
        name: (map['name'] as String?) ?? '',
        sources: (map['sources'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
        logo: map['logo'] as String?,
        group: map['group'] as String?,
      );
}
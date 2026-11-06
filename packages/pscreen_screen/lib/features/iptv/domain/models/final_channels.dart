import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 服务端合并后的最终频道列表（`/api/screen/final_channels.json`）。
///
/// 频道已按规则完成合并 / 隐藏 / 排序 / 强制移除源，客户端只保留家长模式
/// 与「清理失效源」过滤。字段保留多源结构 `name / group / logo / sources`。
class FinalChannelsPayload {
  const FinalChannelsPayload({
    required this.version,
    required this.updatedAt,
    required this.channels,
    required this.protectedSources,
  });

  /// 内容哈希；也作为 HTTP ETag 的取值来源。
  final String version;

  /// 服务端参与合成的文件最新修改时间（毫秒）。
  final int updatedAt;

  final List<IptvChannel> channels;

  /// `not_remove_source.txt` 内容：设备侧「清理失效源」时豁免这些地址。
  final List<String> protectedSources;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'updatedAt': updatedAt,
        'channels': <Map<String, dynamic>>[
          for (final IptvChannel c in channels)
            <String, dynamic>{
              'name': c.name,
              'group': c.group ?? '',
              'logo': c.logo ?? '',
              'sources': c.sources,
            },
        ],
        'protectedSources': protectedSources,
      };

  factory FinalChannelsPayload.fromJson(Map<String, dynamic> json) {
    final Object? rawChannels = json['channels'];
    if (rawChannels is! List || rawChannels.isEmpty) {
      throw const FormatException('频道列表为空');
    }
    final List<IptvChannel> channels = <IptvChannel>[];
    for (final Object? item in rawChannels) {
      if (item is! Map) throw const FormatException('频道条目格式异常');
      final Object? name = item['name'];
      final Object? sources = item['sources'];
      if (name is! String || name.trim().isEmpty) {
        throw const FormatException('频道名格式异常');
      }
      if (sources is! List) throw const FormatException('频道源格式异常');
      final List<String> urls = <String>[];
      for (final Object? url in sources) {
        if (url is! String || url.trim().isEmpty) {
          throw const FormatException('频道源地址格式异常');
        }
        urls.add(url.trim());
      }
      if (urls.isEmpty) throw const FormatException('频道源为空');
      final Object? group = item['group'];
      final Object? logo = item['logo'];
      channels.add(IptvChannel(
        name: name.trim(),
        sources: urls,
        group: group is String && group.isNotEmpty ? group : null,
        logo: logo is String && logo.isNotEmpty ? logo : null,
      ));
    }
    final Object? version = json['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('版本号缺失');
    }
    final Object? updatedAt = json['updatedAt'];
    final List<String> protected = <String>[];
    final Object? rawProtected = json['protectedSources'];
    if (rawProtected is List) {
      for (final Object? url in rawProtected) {
        if (url is String && url.isNotEmpty) protected.add(url);
      }
    }
    return FinalChannelsPayload(
      version: version,
      updatedAt: updatedAt is num ? updatedAt.toInt() : 0,
      channels: channels,
      protectedSources: protected,
    );
  }
}

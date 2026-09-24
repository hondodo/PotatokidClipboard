/// IPTV 频道模型（来自 m3u 播放列表，非 JSON API，故用轻量不可变类）。
class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
  });

  /// 频道名称
  final String name;

  /// 直播流地址（http(s)/rtsp 等）
  final String url;

  /// 台标（`tvg-logo`），可能为空
  final String? logo;

  /// 分组（`group-title`），可能为空
  final String? group;

  @override
  bool operator ==(Object other) =>
      other is IptvChannel && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(url, name);
}
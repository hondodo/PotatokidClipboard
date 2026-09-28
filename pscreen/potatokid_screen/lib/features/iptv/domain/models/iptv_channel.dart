/// IPTV 频道模型（来自 m3u 播放列表，非 JSON API，故用轻量不可变类）。
///
/// 同一个频道（同名）在播放列表里常出现多个可用源（每条一个 URL），
/// 解析时按名称合并为**一个条目**，所有的源按出现顺序存于 [sources]。
class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.sources,
    this.logo,
    this.group,
  });

  /// 频道名称
  final String name;

  /// 播放源地址列表（按优先级，首个优先；播放失败可回退到下一个）
  final List<String> sources;

  /// 台标（`tvg-logo`），可能为空；合并时取首个非空
  final String? logo;

  /// 分组（`group-title`），可能为空；合并时取首个非空
  final String? group;

  /// 主源地址（首个），便于仅需单一地址的场景。
  String get primaryUrl => sources.isEmpty ? '' : sources.first;

  @override
  bool operator ==(Object other) =>
      other is IptvChannel && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 手写 M3U 播放列表解析器。
///
/// M3U 结构：`#EXTINF:` 描述行（可含 `tvg-logo=`、`group-title=`），
/// 紧随其后的一行是频道流地址。解析器逐行扫描并忽略 `#EXTGRP` 等其它注释行。
///
/// 同一频道（同名）在播放列表里可能出现在多个分组、每条一个源 URL。
/// [parse] 会按**名称**把散落的条目合并为一个 [IptvChannel]，将其 URL 收集到
/// [IptvChannel.sources]，从而避免把每个源当成独立「频道」导致列表膨胀、
/// 换台要一路扫过所有源。（首个出现的 logo/分组保留，重复 URL 去重。）
class IptvM3uParser {
  const IptvM3uParser._();

  /// 解析 m3u 文本，返回按名称去重聚合后的频道列表。
  static List<IptvChannel> parse(String content) {
    // 保留首个出现的顺序，用于稳定排序。
    final Map<String, _RawEntry> byName = <String, _RawEntry>{};
    final List<String> order = <String>[];

    // 用 \n 切开并统一去掉行尾 \r，兼容 Windows/Unix 换行。
    final List<String> lines = content
        .split('\n')
        .map((String l) => l.trim())
        .toList(growable: false);

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (!line.startsWith('#EXTINF:')) continue;

      final _ParsedEntry? entry = _parseEntry(lines, i);
      if (entry == null || entry.name.isEmpty || entry.url.isEmpty) continue;
      // Guovin 等播放列表会在开头插入一条 group-title 为「🕘️更新时间」的条目，
      // 其「频道名」实际是时间戳，属元信息而非频道，直接忽略。
      if (_isMetaEntry(entry.group)) continue;

      final _RawEntry? existing = byName[entry.name];
      if (existing == null) {
        byName[entry.name] = _RawEntry(
          name: entry.name,
          logo: entry.logo,
          group: entry.group,
          url: entry.url,
        );
        order.add(entry.name);
      } else {
        existing.addUrl(entry.url);
      }
    }

    return <IptvChannel>[
      for (final String name in order)
        byName[name]!.toChannel(),
    ];
  }

  /// 是否为播放列表的元信息条目（非真实频道）。
  /// 目前指 Guovin 输出的 `group-title` 含「更新时间」的时间戳条目。
  static bool _isMetaEntry(String? group) =>
      group != null && group.contains('更新时间');

  static _ParsedEntry? _parseEntry(List<String> lines, int index) {
    final String inf = lines[index];
    final String attrPart = inf.substring('#EXTINF:'.length).trim();

    // 提取属性：tvg-logo="..." 、 group-title="..."
    final String? logo = _attribute(attrPart, 'tvg-logo');
    final String? group = _attribute(attrPart, 'group-title');

    // 名称：取逗号之后的部分（m3u 约定频道名在最后一个逗号后）。
    final String name = _name(attrPart);

    // 流地址：当前行之后第一个非空且非注释的行。
    String? url;
    for (int j = index + 1; j < lines.length; j++) {
      final String candidate = lines[j];
      if (candidate.isEmpty) continue;
      if (candidate.startsWith('#')) break; // 新条目，本频道无地址
      url = candidate;
      break;
    }
    if (url == null || url.isEmpty || name.isEmpty) return null;

    return _ParsedEntry(name: name, url: url, logo: logo, group: group);
  }

  static String? _attribute(String attrPart, String key) {
    final RegExp regex = RegExp('$key="([^"]*)"', caseSensitive: false);
    final Match? match = regex.firstMatch(attrPart);
    final String? value = match?.group(1);
    return (value == null || value.isEmpty) ? null : value;
  }

  static String _name(String attrPart) {
    final int comma = attrPart.lastIndexOf(',');
    if (comma < 0 || comma == attrPart.length - 1) return '';
    return attrPart.substring(comma + 1).trim();
  }
}

/// 解析出的单个 m3u 条目（一条 EXTINF + 一个 URL）。
class _ParsedEntry {
  const _ParsedEntry({
    required this.name,
    required this.url,
    this.logo,
    this.group,
  });

  final String name;
  final String url;
  final String? logo;
  final String? group;
}

/// 解析过程中用于按名称聚合的可变中间对象。
class _RawEntry {
  _RawEntry({
    required this.name,
    required this.logo,
    required this.group,
    required String url,
  }) : _sources = <String>[url];

  final String name;
  String? logo;
  String? group;
  final List<String> _sources;

  void addUrl(String url) {
    if (!_sources.contains(url)) _sources.add(url);
  }

  IptvChannel toChannel() => IptvChannel(
        name: name,
        sources: _sources,
        logo: logo,
        group: group,
      );
}
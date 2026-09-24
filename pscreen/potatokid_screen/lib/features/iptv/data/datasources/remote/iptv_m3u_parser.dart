import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 手写 M3U 播放列表解析器。
///
/// M3U 结构：`#EXTINF:` 描述行（可含 `tvg-logo=`、`group-title=`），
/// 紧随其后的一行是频道流地址。解析器逐行扫描并忽略 `#EXTGRP` 等其它注释行。
class IptvM3uParser {
  const IptvM3uParser._();

  /// 解析 m3u 文本，返回频道列表。无法识别的行会被跳过。
  static List<IptvChannel> parse(String content) {
    final List<IptvChannel> result = <IptvChannel>[];
    // 用 \n 切开并统一去掉行尾 \r，兼容 Windows/Unix 换行。
    final List<String> lines = content
        .split('\n')
        .map((String l) => l.trim())
        .toList(growable: false);

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (!line.startsWith('#EXTINF:')) continue;

      final IptvChannel? channel = _parseEntry(lines, i);
      if (channel != null) {
        result.add(channel);
      }
    }
    return result;
  }

  static IptvChannel? _parseEntry(List<String> lines, int index) {
    final String inf = lines[index];
    final String attrPart =
        inf.substring('#EXTINF:'.length).trim();

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

    return IptvChannel(name: name, url: url, logo: logo, group: group);
  }

  static String? _attribute(String attrPart, String key) {
    final RegExp regex =
        RegExp('$key="([^"]*)"', caseSensitive: false);
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
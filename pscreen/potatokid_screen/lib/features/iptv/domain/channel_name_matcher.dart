import 'package:potatokid_screen/features/iptv/domain/channel_name_normalizer.dart';

/// 频道名隐藏规则匹配器（`tv_name_hide.txt`）。
///
/// 两种写法：
/// - **精确全等**：`CCTV-5`、`凤凰资讯` —— 名字一字不差才命中（大小写敏感，
///   与历史行为一致，避免老规则因为大小写放宽而误伤）；
/// - **星号通配**：`*咪咕*`（包含）、`咪咕*`（前缀）、`*咪咕`（后缀）、
///   `*a*b*`（按顺序出现）。通配匹配**忽略大小写**——遥控器上很难分辨
///   `NewTV` / `NewTv` 这类写法。
///
/// 规则条目与被匹配的名字都会先过 [normalizeChannelName]，所以
/// `CCTV-1` 能隐藏接口给的 `CCTV1`，写 `CCTV1` 也照样命中
/// （通配条目按片段各自归一化，`*CCTV1*` 同样有效）。
///
/// 只有 `*` 有特殊含义，其余字符（含 `.` `+` `(` `[` 等）一律按字面处理，
/// 所以规则文件不会退化成正则，也不会出现意外匹配。
/// 整条只由 `*` 组成的模式（例如误写一个 `*`）视为无效并忽略——
/// 否则它会匹配任何名字，等于把整个频道列表隐藏掉。
class ChannelNameMatcher {
  /// 按规则清单构建；空白条目自动忽略。
  ChannelNameMatcher(Iterable<String> patterns) {
    for (final String raw in patterns) {
      final String pattern = raw.trim();
      if (pattern.isEmpty) continue;
      if (!pattern.contains('*')) {
        _exact.add(normalizeChannelName(pattern));
        continue;
      }
      final List<String> segments = pattern
          .split('*')
          .map(normalizeChannelName)
          .map((String s) => s.toLowerCase())
          .toList(growable: false);
      // 纯 `*`（全为空片段）会匹配任何名字，忽略。
      if (segments.every((String s) => s.isEmpty)) continue;
      _globs.add(segments);
    }
  }

  /// 精确全等的名字（大小写敏感）。
  final Set<String> _exact = <String>{};

  /// 通配模式：由 `*` 切出的字面片段（已转小写），需按顺序出现。
  final List<List<String>> _globs = <List<String>>[];

  /// 是否一条有效规则都没有。
  bool get isEmpty => _exact.isEmpty && _globs.isEmpty;

  /// 有效规则条数（精确 + 通配）。
  int get length => _exact.length + _globs.length;

  /// 该频道名是否命中隐藏规则（名字先做同样的归一化，写法不影响命中）。
  bool matches(String rawName) {
    if (rawName.isEmpty) return false;
    final String name = normalizeChannelName(rawName);
    if (name.isEmpty) return false;
    if (_exact.contains(name)) return true;
    if (_globs.isEmpty) return false;
    final String lower = name.toLowerCase();
    for (final List<String> segments in _globs) {
      if (_matchesGlob(lower, segments)) return true;
    }
    return false;
  }

  /// 片段按顺序出现即命中；模式不以 `*` 开头 / 结尾时，首 / 末片段还要贴住名字两端。
  static bool _matchesGlob(String name, List<String> segments) {
    // 模式不以 `*` 结尾 → 末片段必须贴在名字结尾。
    final bool anchorEnd = segments.last.isNotEmpty;
    int from = 0;
    for (int i = 0; i < segments.length; i++) {
      final String segment = segments[i];
      if (segment.isEmpty) continue;
      if (i == segments.length - 1 && anchorEnd) {
        // 末片段用 endsWith 判定：同一个片段在名字里可能出现多次，
        // 只有「贴在结尾」的那次才满足，且起点不能早于前面已消费的位置。
        return name.endsWith(segment) && name.length - segment.length >= from;
      }
      final int at = name.indexOf(segment, from);
      if (at < 0) return false;
      // 模式不以 `*` 开头 → 首片段必须是前缀。
      if (i == 0 && at != 0) return false;
      from = at + segment.length;
    }
    return true;
  }
}

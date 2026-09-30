import 'package:flutter/services.dart' show rootBundle;

/// 包内「源规则」清单（全局单例，内容固定、只读一次）。
///
/// - [removeSourcePath]：**强制移除**的源地址（每行一个，**整行完全相等**才命中）。
///   无论「清理失效源」开关是否开启，这些地址都不会出现在频道列表里；
/// - [removeSourceContainsPath]：**强制移除**的源地址片段（每行一个，源地址
///   **包含**其中任意一行即命中）；
/// - [notRemoveSourcePath]：**强制保留**的源地址（每行一个）。永远不会被判定
///   失效而自动移除（即使用户的失效黑名单里已有它）。
///
/// 三个文件都支持空行与 `#` 起始的注释行；文件缺失/读取失败按「无规则」处理，
/// 不阻断频道加载。
class IptvSourceRules {
  IptvSourceRules._();

  /// 全局单例。
  static final IptvSourceRules instance = IptvSourceRules._();

  /// 强制移除清单（整行相等）。
  static const String removeSourcePath = 'assets/datas/remove_source.txt';

  /// 强制移除清单（源地址包含即命中）。
  static const String removeSourceContainsPath = 'assets/datas/remove_source_contains.txt';

  /// 强制保留清单。
  static const String notRemoveSourcePath = 'assets/datas/not_remove_source.txt';

  /// 首次加载的 Future；并发调用共享同一次加载。
  Future<void>? _loading;

  Set<String> _removed = <String>{};
  Set<String> _removedContains = <String>{};
  Set<String> _protected = <String>{};

  /// 强制移除的源地址（整行相等，始终不出现在列表里）。
  Set<String> get removedUrls => _removed;

  /// 强制移除的源地址片段（源地址包含任意一条即移除）。
  Set<String> get removedContainsPatterns => _removedContains;

  /// 强制保留的源地址（不会被自动移除）。
  Set<String> get protectedUrls => _protected;

  /// 加载三份清单（仅首次真正读取）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _removed = await _loadUrlSet(removeSourcePath);
    _removedContains = await _loadUrlSet(removeSourceContainsPath);
    _protected = await _loadUrlSet(notRemoveSourcePath);
  }

  /// 读取「每行一个地址」的清单；空行与 `#` 注释行忽略。
  static Future<Set<String>> _loadUrlSet(String path) async {
    try {
      final String raw = await rootBundle.loadString(path);
      return raw
          .split('\n')
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty && !line.startsWith('#'))
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
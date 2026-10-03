import 'package:potatokid_screen/app/config/data_files.dart';

/// 源规则清单（全局单例），内容由 [DataFiles] 提供：
/// git 同步结果 → 本地缓存 → 包内 `assets/datas` 默认值。
///
/// 三份清单（均为「每行一个」，支持空行与 `#` 起始的注释行）：
/// - `remove_source.txt`：**强制移除**的源地址。**整行完全相等**才命中，
///   无论「清理失效源」开关是否开启，这些地址都不会出现在频道列表里；
/// - `remove_source_contains.txt`：**强制移除**的源地址片段，源地址
///   **包含**其中任意一行即命中；
/// - `not_remove_source.txt`：**强制保留**的源地址。永远不会被判定失效
///   而自动移除（即使用户的失效黑名单里已有它）。
///
/// 内容缺失/读取失败按「无规则」处理，不阻断频道加载。
class IptvSourceRules {
  IptvSourceRules._();

  /// 全局单例。
  static final IptvSourceRules instance = IptvSourceRules._();

  /// 并发调用共享的加载 Future。
  Future<void>? _loading;

  /// 上次解析时 [DataFiles.revision] 的值：内容变过就重新解析，
  /// 这样「刷新频道」拉到的 git 新规则才会生效。
  int _loadedRevision = -1;

  Set<String> _removed = <String>{};
  Set<String> _removedContains = <String>{};
  Set<String> _protected = <String>{};

  /// 强制移除的源地址（整行相等，始终不出现在列表里）。
  Set<String> get removedUrls => _removed;

  /// 强制移除的源地址片段（源地址包含任意一条即移除）。
  Set<String> get removedContainsPatterns => _removedContains;

  /// 强制保留的源地址（不会被自动移除）。
  Set<String> get protectedUrls => _protected;

  /// 加载三份清单；内容未变时直接复用上次结果。
  Future<void> ensureLoaded() {
    final Future<void>? inFlight = _loading;
    if (inFlight != null) return inFlight;
    if (_loadedRevision == DataFiles.instance.revision) {
      return Future<void>.value();
    }
    return _loading = _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    // 数据文件由 DataFiles 统一提供；幂等且只做本地 IO，很快。
    await DataFiles.instance.loadLocal();
    _removed = parseLineSet(DataFiles.instance.text(DataFiles.idRemoveSource));
    _removedContains = parseLineSet(DataFiles.instance.text(DataFiles.idRemoveSourceContains));
    _protected = parseLineSet(DataFiles.instance.text(DataFiles.idNotRemoveSource));
    _loadedRevision = DataFiles.instance.revision;
  }
}
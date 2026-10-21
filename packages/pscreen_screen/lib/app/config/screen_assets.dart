/// 共享包内资产路径的根前缀。
///
/// Flutter 只把**宿主** pubspec 中声明的资产打进 bundle；依赖包的资产必须由
/// 宿主以 `packages/<包名>/...` 形式声明，且包内代码要用同样的前缀读取。
/// 因此这里把前缀做成可配置：包自身跑测试时为空，宿主接入时设为
/// `packages/pscreen_screen/`。
///
/// **使用约定**：[path] 应在**读取资产的那一刻**调用，不要把结果缓存下来 ——
/// 宿主可能在首次读取之后才调用 [configure]。
class ScreenAssets {
  const ScreenAssets._();

  /// 资产根前缀，末尾恒为 `/`。
  static String _root = '';

  /// 当前根前缀。
  static String get root => _root;

  /// 是否已配置根前缀。
  ///
  /// 宿主**必须**在读取任何共享包资产之前调用 [configure]：忘记配置会让所有
  /// 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、城市列表为空」
  /// 这类静默故障。用 [requireConfigured] 把这种失败变成显式异常。
  static bool get isConfigured => _root.isNotEmpty;

  /// 设置根前缀：自动补尾部 `/`、去掉头部 `/`。
  static void configure({required String root}) {
    var normalized = root.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    _root = normalized.isEmpty ? '' : '$normalized/';
  }

  /// 断言根前缀已配置；未配置时抛 [StateError]。
  ///
  /// 由共享包内**唯一的资产读取点**调用（`DataFiles._readAsset`），把
  /// 「宿主忘记 configure」从静默降级变成显式失败。
  static void requireConfigured() {
    if (_root.isEmpty) {
      throw StateError(
        'ScreenAssets 未配置：宿主必须先调用 '
        'ScreenAssets.configure(root: "packages/pscreen_screen/")，'
        '否则依赖包的资产无法被读取。',
      );
    }
  }

  /// 拼出最终可被 `rootBundle.load` 读取的路径。
  ///
  /// [relative] 里的前导斜杠会被去掉，避免与根前缀拼出双斜杠。
  static String path(String relative) {
    var rel = relative.trim();
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    return '$_root$rel';
  }
}

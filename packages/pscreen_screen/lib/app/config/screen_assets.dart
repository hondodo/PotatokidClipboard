/// 共享包内资产路径的根前缀。
///
/// 共享包自己的 `pubspec.yaml` 已声明 `assets: - assets/datas/`；作为依赖被引入时
/// flutter_tools 会展开该目录并给资产键加上 `packages/<包名>/` 前缀，所以宿主
/// **不需要**再在自己的 pubspec 里声明这份资产。包内代码要用同样的前缀读取，
/// 因此这里把前缀做成可配置。
///
/// 两种场景的根前缀不同：
/// - **共享包自身**（跑自己的 `flutter test`）：根前缀为空 `''`，资产键就是
///   `assets/datas/x.txt`（包自己的 pubspec 声明了 `assets/datas/`）。
/// - **宿主 App**：根前缀为 `packages/pscreen_screen/`，资产键是
///   `packages/pscreen_screen/assets/datas/x.txt`。
///
/// **使用约定**：[path] 应在**读取资产的那一刻**调用，不要把结果缓存下来 ——
/// 宿主可能在首次读取之后才调用 [configure]。
class ScreenAssets {
  const ScreenAssets._();

  /// 资产根前缀，末尾恒为 `/`。
  static String _root = '';

  /// 是否已调用过 [configure]（与根前缀是否为空无关）。
  static bool _configured = false;

  /// 当前根前缀。
  static String get root => _root;

  /// 宿主是否已完成接入配置（调用过 [configure]）。
  ///
  /// 宿主**必须**在读取任何共享包资产之前调用 [configure]：忘记配置会让所有
  /// 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、城市列表为空」
  /// 这类静默故障。宿主用 [requireHostConfigured] 在启动期把它变成显式失败。
  static bool get isConfigured => _configured;

  /// 设置根前缀：自动补尾部 `/`、去掉头部 `/`。
  ///
  /// 传入空串是合法的（共享包自身场景）。
  static void configure({required String root}) {
    var normalized = root.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    _root = normalized.isEmpty ? '' : '$normalized/';
    _configured = true;
  }

  /// 宿主接入自检：根前缀为空时抛 [StateError]。
  ///
  /// **只在宿主启动路径调用**（紧接 [configure] 之后）——共享包自身跑测试时
  /// 根前缀为空是合法的。放在启动期的好处是「忘记 configure」立刻失败，
  /// 而不是等到第一次读资产时被 `catch` 吞掉、变成运行期的静默降级。
  static void requireHostConfigured() {
    if (_root.isEmpty) {
      throw StateError(
        'ScreenAssets 未配置：宿主必须先调用 '
        'ScreenAssets.configure(root: "packages/pscreen_screen/")，'
        '并在其后调用 ScreenAssets.requireHostConfigured() 做接入自检；'
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

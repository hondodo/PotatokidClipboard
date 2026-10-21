/// 共享包内资产路径的根前缀。
///
/// Flutter 只把**宿主** pubspec 中声明的资产打进 bundle；依赖包的资产必须由
/// 宿主以 `packages/<包名>/...` 形式声明，且包内代码要用同样的前缀读取。
/// 因此这里把前缀做成可配置：包自身跑测试时为空，宿主接入时设为
/// `packages/pscreen_screen/`。
class ScreenAssets {
  const ScreenAssets._();

  /// 资产根前缀，末尾恒为 `/`。
  static String _root = '';

  /// 当前根前缀。
  static String get root => _root;

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

  /// 拼出最终可被 `rootBundle.load` 读取的路径。
  static String path(String relative) => '$_root$relative';
}

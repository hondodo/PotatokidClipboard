import 'package:pscreen_screen/core/di/get_it.dart';

/// 共享包的依赖解析门面。
///
/// 两个宿主（`pscreen_home` / `potatokid_screen`）都使用 `GetIt.instance`
/// 全局单例，因此共享包无需持有 DI 根，直接复用同一实例即可。
/// 宿主在 `Injection.init()` 中调用 `ScreenModules.register(getIt)` 完成注册。
class ScreenInjection {
  const ScreenInjection._();

  static T get<T extends Object>() => getIt<T>();
}

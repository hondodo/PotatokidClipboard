import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 屏幕模块：注册宿主侧的场景描述器。
///
/// 必须在共享包的 `ScreenModules.register` **之前**调用——共享包的
/// `MsgModule` 会立刻读取 `CurrentSceneProvider`。
class ScreenModule {
  const ScreenModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<CurrentSceneProvider>(
      () => const HomeSceneProvider(),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<CurrentSceneProvider>();
  }
}

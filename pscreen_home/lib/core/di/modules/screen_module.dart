import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 屏幕模块：注册宿主侧的场景描述器。
///
/// 必须在共享包的 `ScreenModules.register` **之前**调用——共享包的
/// `MsgModule` 会立刻读取 `CurrentSceneProvider`。
class ScreenModule {
  const ScreenModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<CurrentSceneProvider>(
      () => HomeSceneProvider(
        // 本模块最早注册，Router/Storage/Home 都还没注册，必须惰性取值。
        router: () => getIt<AppRouter>(),
        screensaver: () => getIt<ScreensaverController>(),
        homeBloc: () => getIt<HomeBloc>(),
      ),
    );
  }

  static Future<void> unregister() async {
    if (getIt.isRegistered<CurrentSceneProvider>()) {
      final CurrentSceneProvider provider = getIt<CurrentSceneProvider>();
      if (provider is HomeSceneProvider) provider.dispose();
      await getIt.unregister<CurrentSceneProvider>();
    }
  }
}

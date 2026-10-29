import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/home_navigator.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 屏幕模块：注册宿主侧的场景描述器与导航能力。
///
/// 必须在共享包的 `ScreenModules.register` **之前**调用——共享包的
/// `MsgModule` 会立刻读取 `CurrentSceneProvider` 与 `HostNavigator`。
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
    // 遥控端 `nav` 命令：主页/直播/天气/设置/屏保切换。
    getIt.registerLazySingleton<HostNavigator>(
      () => HomeNavigator(
        router: () => getIt<AppRouter>(),
        screensaver: () => getIt<ScreensaverController>(),
      ),
    );
  }

  static Future<void> unregister() async {
    if (getIt.isRegistered<HostNavigator>()) {
      await getIt.unregister<HostNavigator>();
    }
    if (getIt.isRegistered<CurrentSceneProvider>()) {
      final CurrentSceneProvider provider = getIt<CurrentSceneProvider>();
      if (provider is HomeSceneProvider) provider.dispose();
      await getIt.unregister<CurrentSceneProvider>();
    }
  }
}

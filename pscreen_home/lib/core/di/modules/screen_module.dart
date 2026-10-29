import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/home_navigator.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 屏幕模块：注册宿主侧的场景描述器与导航能力。
///
/// 必须在共享包的 `ScreenModules.register` **之前**调用——共享包的
/// `MsgModule` 会立刻读取 `CurrentSceneProvider` 与 `HostNavigator`。
class ScreenModule {
  const ScreenModule._();

  static Future<void> register() async {
    // 全局直播窗口：播放器由 MaterialApp.builder 里的 LiveStageHost 渲染，
    // 全屏 / 悬浮只是位置变化，切换形态不重建播放器。
    getIt.registerLazySingleton<LiveStageController>(
      () => LiveStageController(router: () => getIt<AppRouter>()),
    );
    getIt.registerLazySingleton<CurrentSceneProvider>(
      () => HomeSceneProvider(
        // 本模块最早注册，Router/Storage/Home 都还没注册，必须惰性取值。
        router: () => getIt<AppRouter>(),
        screensaver: () => getIt<ScreensaverController>(),
        homeBloc: () => getIt<HomeBloc>(),
        live: () => getIt<LiveStageController>(),
      ),
    );
    // 遥控端 `nav` 命令：主页/直播/天气/设置/屏保切换。
    getIt.registerLazySingleton<HostNavigator>(
      () => HomeNavigator(
        router: () => getIt<AppRouter>(),
        screensaver: () => getIt<ScreensaverController>(),
        live: () => getIt<LiveStageController>(),
      ),
    );
    // 定时关闭在中控屏的语义：到点关闭直播（含悬浮小窗）/屏保回到主页，
    // 而不是退出应用。
    SleepTimerController.instance.onExpire = () {
      final ScreensaverController screensaver = getIt<ScreensaverController>();
      if (screensaver.active) screensaver.active = false;
      getIt<LiveStageController>().close(goTo: RouteNames.home);
    };
  }

  static Future<void> unregister() async {
    SleepTimerController.instance.onExpire = null;
    if (getIt.isRegistered<HostNavigator>()) {
      await getIt.unregister<HostNavigator>();
    }
    if (getIt.isRegistered<CurrentSceneProvider>()) {
      final CurrentSceneProvider provider = getIt<CurrentSceneProvider>();
      if (provider is HomeSceneProvider) provider.dispose();
      await getIt.unregister<CurrentSceneProvider>();
    }
    if (getIt.isRegistered<LiveStageController>()) {
      await getIt.unregister<LiveStageController>();
    }
  }
}

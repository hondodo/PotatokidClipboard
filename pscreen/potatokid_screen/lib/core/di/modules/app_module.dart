import 'package:potatokid_screen/core/app_exit_controller.dart';
import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/tv_navigator.dart';
import 'package:potatokid_screen/features/app/application/tv_scene_provider.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 应用级模块：注册全局 Bloc（无依赖，可最先注册）
class AppModule {
  const AppModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<AppBloc>(() => AppBloc());
    // 电视端有 4-tab 外壳，场景描述 = 当前 Tab 页名。
    // 必须在 ScreenModules.register（内部会用到）之前完成注册。
    getIt.registerLazySingleton<CurrentSceneProvider>(
      () => const TvSceneProvider(),
    );
    // 远程 nav 指令 → 切换顶部 Tab（MessageModule 注册命令执行器前可用）。
    getIt.registerLazySingleton<HostNavigator>(() => const TvNavigator());
    // 电视端定时关闭：到点退出**整个应用**（中控屏注入的是「关直播回主页」，
    // 到点动作由各宿主注入，见共享包 SleepTimerController.onExpire）。
    SleepTimerController.instance.onExpire = AppExitController.instance.exit;
  }

  static Future<void> unregister() async {
    SleepTimerController.instance.onExpire = null;
    await getIt.unregister<HostNavigator>();
    await getIt.unregister<CurrentSceneProvider>();
    await getIt.unregister<AppBloc>();
  }
}

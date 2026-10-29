import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    // 电视端定时关闭：默认动作是退出 App。Android 上 SystemNavigator.pop()
    // 只 finish 当前 Activity，遇到多 task / 桌面栈会看起来没退出；这里改走
    // 原生 finishAndRemoveTask + 杀进程。桌面端 SystemNavigator.pop 本身
    // 就会结束进程。
    SleepTimerController.instance.onExpire = () {
      if (defaultTargetPlatform == TargetPlatform.android) {
        const MethodChannel('potatokid/app')
            .invokeMethod<void>('exitApp')
            .catchError((Object _) => SystemNavigator.pop());
      } else {
        // Windows / Linux / macOS 的 SystemNavigator.pop 会直接结束进程。
        SystemNavigator.pop();
      }
    };
  }

  static Future<void> unregister() async {
    SleepTimerController.instance.onExpire = null;
    await getIt.unregister<HostNavigator>();
    await getIt.unregister<CurrentSceneProvider>();
    await getIt.unregister<AppBloc>();
  }
}

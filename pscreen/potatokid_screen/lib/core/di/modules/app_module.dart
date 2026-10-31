import 'dart:io' as io;

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
    // 电视端定时关闭：到点退出**整个应用**（中控屏注入的是「关直播回主页」，
    // 到点动作由各宿主注入，见共享包 SleepTimerController.onExpire）。
    SleepTimerController.instance.onExpire = _exitApp;
  }

  static Future<void> unregister() async {
    SleepTimerController.instance.onExpire = null;
    await getIt.unregister<HostNavigator>();
    await getIt.unregister<CurrentSceneProvider>();
    await getIt.unregister<AppBloc>();
  }
}

/// 退出整个应用（电视端定时关闭的到点动作）。
///
/// - **Android**：走原生 `potatokid/app` → `exitApp`（finishAndRemoveTask + 结束进程）。
///   `SystemNavigator.pop()` 只 finish 当前 Activity，遇到多 task / 桌面栈
///   看起来像没退；原生通道不可用时才退回它。
/// - **桌面（Windows 调试 / Linux / macOS）**：直接结束进程。实测（Windows 引擎）：
///   ① `SystemNavigator.pop()` 3ms 内返回但**什么都不做**，App 不退出——这正是
///   定时到点“不生效”的根因；② `ServicesBinding.exitApplication(required)` 会以
///   0xc0000005 访问违规把进程弄崩（flutter_windows.dll），属崩溃而非干净退出。
///   故桌面走 `exit(0)`：进程以退出码 0 立即结束，不产生崩溃弹窗/WER 记录。
Future<void> _exitApp() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await const MethodChannel('potatokid/app').invokeMethod<void>('exitApp');
      return;
    } catch (_) {
      // 原生退出通道不可用 → 退回结束 Activity。
      await SystemNavigator.pop();
      return;
    }
  }
  io.exit(0);
}

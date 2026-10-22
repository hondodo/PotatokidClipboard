import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/utils/app_version.dart';
import 'package:pscreen_screen/core/utils/nim_manager.dart';

/// 核心模块：注册启动期就绪的基础服务（应用版本信息、网易云信 NIM 单例）。
///
/// 与其它 Module 一致的注册/注销成对写法；注册时直接 await
/// [AppVersion.load]，保证第一个页面 build 时版本号已就绪（设置页直接读字符串）。
class CoreModule {
  const CoreModule._();

  static Future<void> register(GetIt it) async {
    it.registerSingleton<AppVersion>(await AppVersion.load());
    // 网易云信 NIM：只注册单例，不在注册阶段初始化（初始化在 main 中非阻塞触发）。
    it.registerSingleton<NimManager>(NimManager());
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<NimManager>();
    await it.unregister<AppVersion>();
  }
}

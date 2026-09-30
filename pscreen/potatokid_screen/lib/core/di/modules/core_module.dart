import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/utils/app_version.dart';

/// 核心模块：注册启动期就绪的基础服务（当前为应用版本信息）。
///
/// 与其它 Module 一致的注册/注销成对写法；注册时直接 await
/// [AppVersion.load]，保证第一个页面 build 时版本号已就绪（设置页直接读字符串）。
class CoreModule {
  const CoreModule._();

  static Future<void> register() async {
    getIt.registerSingleton<AppVersion>(await AppVersion.load());
  }

  static Future<void> unregister() async {
    await getIt.unregister<AppVersion>();
  }
}

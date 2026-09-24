import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/di/modules/app_module.dart';
import 'package:potatokid_screen/core/di/modules/home_module.dart';
import 'package:potatokid_screen/core/di/modules/network_module.dart';
import 'package:potatokid_screen/core/di/modules/router_module.dart';

/// 依赖注入门面：按固定顺序编排各 Module 的注册/注销。
/// 业务代码统一通过 `Injection.get<T>()` 获取实例。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await GetItConfig.init();
    await NetworkModule.register();
    await RouterModule.register();
    await AppModule.register();
    await HomeModule.register();
  }

  static Future<void> reset() async {
    await HomeModule.unregister();
    await AppModule.unregister();
    await RouterModule.unregister();
    await NetworkModule.unregister();
    await GetItConfig.reset();
  }

  static T get<T extends Object>() => getIt<T>();
}

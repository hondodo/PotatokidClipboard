import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/modules/connection_module.dart';
import 'package:pscreen_home/core/di/modules/home_module.dart';
import 'package:pscreen_home/core/di/modules/network_module.dart';
import 'package:pscreen_home/core/di/modules/router_module.dart';
import 'package:pscreen_home/core/di/modules/screen_module.dart';
import 'package:pscreen_home/core/di/modules/storage_module.dart';
import 'package:pscreen_screen/core/di/screen_modules.dart';

/// 依赖注入门面：按固定顺序编排各 Module 的注册/注销。
/// 业务代码统一通过 `Injection.get<T>()` 获取实例。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await GetItConfig.init();
    // 1. 宿主场景描述器（共享包 MsgModule 会立即读取，必须最先）
    await ScreenModule.register();
    // 2. 共享包能力层（内含 LogService / DioManager / NimManager /
    //    IptvBloc / WeatherBloc / RemoteLoginBloc 等）
    await ScreenModules.register(getIt);
    // 3. 宿主模块（NetworkModule 依赖共享包注册的 LogService）
    await StorageModule.register();
    await NetworkModule.register();
    await RouterModule.register();
    await ConnectionModule.register();
    await HomeModule.register();
  }

  static Future<void> reset() async {
    await HomeModule.unregister();
    await ConnectionModule.unregister();
    await RouterModule.unregister();
    await NetworkModule.unregister();
    await StorageModule.unregister();
    await ScreenModules.unregister(getIt);
    await ScreenModule.unregister();
    await GetItConfig.reset();
  }

  static T get<T extends Object>() => getIt<T>();
}

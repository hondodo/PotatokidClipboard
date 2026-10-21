import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/di/modules/core_module.dart';
import 'package:pscreen_screen/core/di/modules/iptv_module.dart';
import 'package:pscreen_screen/core/di/modules/msg_module.dart';
import 'package:pscreen_screen/core/di/modules/network_module.dart';
import 'package:pscreen_screen/core/di/modules/remote_module.dart';
import 'package:pscreen_screen/core/di/modules/weather_module.dart';

/// 共享包的依赖注册入口。
///
/// 宿主在自己的 `Injection.init()` 中调用一次即可。注册顺序不可调换：
/// CoreModule（NimManager / AppVersion）→ NetworkModule（LogService / DioManager）
/// → RemoteModule（NIM 登录）→ MsgModule（收发消息）→ IptvModule → WeatherModule。
///
/// 宿主必须在调用 [register] 之前先注册自己的 CurrentSceneProvider 实现——
/// `MsgModule` 在注册时从 DI 读取它（电视端注册 `TvSceneProvider`，中控屏注册 `HomeSceneProvider`）。
class ScreenModules {
  const ScreenModules._();

  static Future<void> register(GetIt it) async {
    await CoreModule.register();
    await NetworkModule.register();
    await RemoteModule.register();
    await MsgModule.register();
    await IptvModule.register();
    await WeatherModule.register();
  }

  static Future<void> unregister(GetIt it) async {
    await WeatherModule.unregister();
    await IptvModule.unregister();
    await MsgModule.unregister();
    await RemoteModule.unregister();
    await NetworkModule.unregister();
    await CoreModule.unregister();
  }
}

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
///
/// 所有注册都发生在传入的 [it] 容器里（宿主传自己的 `getIt`），
/// 共享包不再隐式依赖包内的全局 `getIt`。
///
/// **注意：注册本类即启用「接收端」链路** —— `MsgModule` 会订阅
/// `NimManager.onReceiveMessages`，把收到并寻址到本 App NIM 账号的指令信封
/// 交给 `MessageCommandExecutor` 执行。详见 README「发送端 / 接收端」一节。
class ScreenModules {
  const ScreenModules._();

  static Future<void> register(GetIt it) async {
    await CoreModule.register(it);
    await NetworkModule.register(it);
    await RemoteModule.register(it);
    await MsgModule.register(it);
    await IptvModule.register(it);
    await WeatherModule.register(it);
  }

  static Future<void> unregister(GetIt it) async {
    await WeatherModule.unregister(it);
    await IptvModule.unregister(it);
    await MsgModule.unregister(it);
    await RemoteModule.unregister(it);
    await NetworkModule.unregister(it);
    await CoreModule.unregister(it);
  }
}

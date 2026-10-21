import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

/// 网络模块：注册 Home Assistant WebSocket 客户端（应用唯一网络入口）。
///
/// `LogService` 由共享包的 `ScreenModules.register` 注册（同一个
/// `GetIt.instance`），此处**不可重复注册**——get_it 对重复注册会直接抛异常。
class NetworkModule {
  const NetworkModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HaWsClient>(
      () => HaWsClient(log: getIt<LogService>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HaWsClient>();
  }
}

import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';

/// 网络模块：注册日志与 Home Assistant WebSocket 客户端（应用唯一网络入口）。
class NetworkModule {
  const NetworkModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<LogService>(() => const LogService());
    getIt.registerLazySingleton<HaWsClient>(
      () => HaWsClient(log: getIt<LogService>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HaWsClient>();
    await getIt.unregister<LogService>();
  }
}

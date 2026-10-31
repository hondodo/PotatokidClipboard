import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 网络模块：注册日志、实时通道与网络访问入口
class NetworkModule {
  const NetworkModule._();

  static Future<void> register(GetIt it) async {
    it.registerLazySingleton<LogService>(() => const LogService());
    it.registerLazySingleton<RealtimeChannel>(() => RealtimeChannel());
    it.registerLazySingleton<DioManager>(() => DioManager());
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<DioManager>();
    if (it.isRegistered<RealtimeChannel>()) {
      await it.get<RealtimeChannel>().dispose();
      await it.unregister<RealtimeChannel>();
    }
    await it.unregister<LogService>();
  }
}

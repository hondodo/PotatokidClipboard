import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';

/// 网络模块：注册日志与网络访问入口
class NetworkModule {
  const NetworkModule._();

  static Future<void> register(GetIt it) async {
    it.registerLazySingleton<LogService>(() => const LogService());
    it.registerLazySingleton<DioManager>(() => DioManager());
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<DioManager>();
    await it.unregister<LogService>();
  }
}

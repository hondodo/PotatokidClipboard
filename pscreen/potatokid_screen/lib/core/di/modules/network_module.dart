import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/dio_manager.dart';

/// 网络模块：注册日志与网络访问入口
class NetworkModule {
  const NetworkModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<LogService>(() => const LogService());
    getIt.registerLazySingleton<DioManager>(() => DioManager());
  }

  static Future<void> unregister() async {
    await getIt.unregister<DioManager>();
    await getIt.unregister<LogService>();
  }
}
